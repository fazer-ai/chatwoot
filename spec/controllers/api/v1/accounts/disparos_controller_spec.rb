require 'rails_helper'

RSpec.describe 'Disparos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  # Beta 0 is hidden behind the DISPARADOR_BETA0_VISIBLE installation config.
  # Default is false; tests opt in/out explicitly. Always call_original first so
  # the rest of the request cycle (auth/locale configs) keeps working.
  def stub_beta0_flag(value)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('DISPARADOR_BETA0_VISIBLE', false).and_return(value)
  end

  describe 'POST /api/v1/accounts/{account.id}/disparos' do
    # Beta 0 is exclusive_cloud: a draft may only link WhatsApp Cloud inboxes. Override
    # the shared (web-widget) inbox with a real cloud inbox so the happy path resolves
    # uniformly across valid_params and every inbox.id assertion in this block.
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                sync_templates: false, validate_provider_config: false).inbox
    end

    # GAP A: the submitted template_category must equal the real category of the
    # approved template in the selected inbox. The factory cloud inbox approves
    # `sample_shipping_confirmation` (legacy SHIPPING_UPDATE -> utility) and the
    # column defaults to utility, so the omitted-category happy path resolves.
    let(:valid_params) do
      {
        disparo: {
          name: 'Reativação',
          description: 'Shadow run',
          template_name: 'sample_shipping_confirmation',
          audience_filter: { kanban_steps: %w[3], label: %w[vip] },
          inbox_ids: [inbox.id]
        }
      }
    end

    context 'when the flag is on' do
      before { stub_beta0_flag(true) }

      context 'when it is an unauthenticated user' do
        it 'returns unauthorized' do
          expect { post "/api/v1/accounts/#{account.id}/disparos", params: valid_params, as: :json }
            .not_to change(Disparo, :count)
          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when it is an authenticated user' do
        it 'persists a draft disparo and its inboxes atomically' do
          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: valid_params, as: :json
          end.to change(Disparo, :count).by(1).and change(DisparoInbox, :count).by(1)

          expect(response).to have_http_status(:created)

          disparo = Disparo.last
          expect(disparo.account).to eq(account)
          expect(disparo).to be_draft
          expect(disparo.created_by).to eq(admin)
          expect(disparo.audience_filter).to eq('kanban_steps' => ['3'], 'label' => ['vip'])
          expect(disparo.disparo_inboxes.pluck(:inbox_id)).to eq([inbox.id])
        end

        it 'returns the created disparo JSON' do
          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: valid_params, as: :json

          body = response.parsed_body
          expect(body['id']).to eq(Disparo.last.id)
          expect(body['status']).to eq('draft')
          expect(body['template_name']).to eq('sample_shipping_confirmation')
          expect(body['inbox_ids']).to eq([inbox.id])
        end

        it 'persists template_category from the create params so the marketing cooldown can fire' do
          # GAP A: a `marketing` submission must match a MARKETING-category approved
          # template in the selected inbox, so use an inbox that approves one.
          marketing_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                      sync_templates: false, validate_provider_config: false,
                                                      message_templates: [{ 'name' => 'promo_blast', 'status' => 'approved',
                                                                            'category' => 'MARKETING' }]).inbox
          params = valid_params.deep_dup
          params[:disparo][:template_name] = 'promo_blast'
          params[:disparo][:template_category] = 'marketing'
          params[:disparo][:inbox_ids] = [marketing_inbox.id]

          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: params, as: :json

          expect(response).to have_http_status(:created)
          expect(Disparo.last.template_category).to eq('marketing')
        end

        it 'defaults template_category to utility when the create params omit it' do
          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: valid_params, as: :json

          expect(response).to have_http_status(:created)
          expect(Disparo.last.template_category).to eq('utility')
        end

        it 'rejects an invalid template_category value with a 422 and creates nothing' do
          params = valid_params.deep_dup
          params[:disparo][:template_category] = 'not_a_category'

          # An out-of-range enum value would raise ArgumentError on assignment; the
          # controller pre-validates it at the boundary so malformed client input is a
          # 4xx (not a 500) and no Disparo is persisted.
          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('invalid_template_category')
        end

        it 'rejects a blank template_name with a 422 and persists nothing (no dead draft)' do
          params = valid_params.deep_dup
          params[:disparo][:template_name] = ''

          # A disparo with no template can never be dry-run/shadow-run (the services
          # require a template) and there is no update action to set one later. Reject
          # the blank template BEFORE persisting so we never leave a dead draft.
          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('invalid_template')
        end

        it 'rejects an absent template_name with a 422 and persists nothing (no dead draft)' do
          params = valid_params.deep_dup
          params[:disparo].delete(:template_name)

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('invalid_template')
        end

        it 'persists conversation_status from the create params' do
          params = valid_params.deep_dup
          params[:disparo][:conversation_status] = 'all'

          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: params, as: :json

          expect(response).to have_http_status(:created)
          disparo = Disparo.last
          expect(disparo.conversation_status).to eq('all')
        end

        it 'defaults conversation_status to open when the create params omit it' do
          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: valid_params, as: :json

          expect(response).to have_http_status(:created)
          disparo = Disparo.last
          expect(disparo.conversation_status).to eq('open')
        end

        it 'rejects an invalid conversation_status value with a 422 and creates nothing' do
          params = valid_params.deep_dup
          params[:disparo][:conversation_status] = 'not_a_status'

          # An out-of-range enum value would raise ArgumentError on assignment; the
          # controller pre-validates it at the boundary so malformed client input is a
          # 4xx (not a 500) and no Disparo is persisted.
          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('invalid_conversation_status')
        end

        # GAP A: the submitted template_category must equal the resolved category
        # of the template in the selected inbox(es) — the backend defends even
        # though the FE derives the category.
        it 'creates the disparo when the submitted category matches the approved template category' do
          # sample_shipping_confirmation is legacy SHIPPING_UPDATE -> utility.
          params = valid_params.deep_dup
          params[:disparo][:template_category] = 'utility'

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to change(Disparo, :count).by(1)

          expect(response).to have_http_status(:created)
          expect(Disparo.last.template_category).to eq('utility')
        end

        it 'rejects with a 422 when the submitted category mismatches (utility submitted for a MARKETING template)' do
          marketing_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                      sync_templates: false, validate_provider_config: false,
                                                      message_templates: [{ 'name' => 'promo_blast', 'status' => 'approved',
                                                                            'category' => 'MARKETING' }]).inbox
          params = valid_params.deep_dup
          params[:disparo][:template_name] = 'promo_blast'
          params[:disparo][:template_category] = 'utility'
          params[:disparo][:inbox_ids] = [marketing_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('template_category_mismatch')
        end

        it 'rejects with a 422 when an omitted category (defaults utility) mismatches a MARKETING template' do
          # A client cannot bypass the marketing cooldown by omitting the category:
          # the EFFECTIVE value (utility) is validated against the real category.
          marketing_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                      sync_templates: false, validate_provider_config: false,
                                                      message_templates: [{ 'name' => 'promo_blast', 'status' => 'approved',
                                                                            'category' => 'MARKETING' }]).inbox
          params = valid_params.deep_dup
          params[:disparo][:template_name] = 'promo_blast'
          params[:disparo].delete(:template_category)
          params[:disparo][:inbox_ids] = [marketing_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('template_category_mismatch')
        end

        it 'rejects with a 422 when the template is not approved in the selected inbox' do
          params = valid_params.deep_dup
          params[:disparo][:template_name] = 'never_synced_template'

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('template_category_mismatch')
        end

        # GAP A end-to-end exact-case: template name handling is case-SENSITIVE
        # the whole way down (TemplateCategory resolver, the engine's
        # inbox_not_approved allowlist and the BulkMarker dedup/cooldown key all
        # key off the RAW name). A mis-cased template_name therefore fails
        # category resolution HERE (no approved entry matches the casing) and is
        # rejected at the door — never persisted, so it can never reach the engine
        # to be mis-marked eligible against a canonical-cased dedup marker (no
        # fail-open).
        it 'rejects with a 422 when the template_name casing differs from the synced approved template and persists nothing' do
          params = valid_params.deep_dup
          params[:disparo][:template_name] = 'sample_shipping_confirmation'.upcase

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('template_category_mismatch')
        end

        it 'rejects with a 422 when the category matches in one selected inbox but not the other (multi-inbox strict)' do
          # inbox approves sample_shipping_confirmation -> utility; the second inbox
          # does NOT carry it, so the submitted utility cannot resolve there.
          second_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                   sync_templates: false, validate_provider_config: false,
                                                   message_templates: []).inbox
          params = valid_params.deep_dup
          params[:disparo][:template_category] = 'utility'
          params[:disparo][:inbox_ids] = [inbox.id, second_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('template_category_mismatch')
        end

        it 'ignores client-supplied status, account_id and created_by_id (mass-assignment guard)' do
          other_account = create(:account)
          tampered = valid_params.deep_dup
          tampered[:disparo].merge!(status: 'running', account_id: other_account.id, created_by_id: 999_999)

          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: tampered, as: :json

          expect(response).to have_http_status(:created)
          disparo = Disparo.last
          expect(disparo).to be_draft
          expect(disparo.account).to eq(account)
          expect(disparo.created_by).to eq(admin)
        end

        it 'rejects an inbox that does not belong to the account (cross-account injection guard)' do
          foreign_inbox = create(:inbox, account: create(:account))
          params = valid_params.deep_dup
          params[:disparo][:inbox_ids] = [foreign_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:not_found)
        end

        it 'rejects a non-Cloud WhatsApp inbox (exclusive_cloud guard at creation)' do
          baileys_inbox = create(:channel_whatsapp, account: account, provider: 'baileys',
                                                    sync_templates: false, validate_provider_config: false).inbox
          params = valid_params.deep_dup
          params[:disparo][:inbox_ids] = [baileys_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('unsupported_inbox_provider')
        end

        it 'rejects atomically when Cloud and non-Cloud inboxes are mixed' do
          baileys_inbox = create(:channel_whatsapp, account: account, provider: 'baileys',
                                                    sync_templates: false, validate_provider_config: false).inbox
          params = valid_params.deep_dup
          params[:disparo][:inbox_ids] = [inbox.id, baileys_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('unsupported_inbox_provider')
        end

        it 'rejects empty inbox_ids with a 422 and persists nothing (no un-runnable draft)' do
          params = valid_params.deep_dup
          params[:disparo][:inbox_ids] = []

          # An empty inbox set is vacuously cloud-valid ([].all? is true), so without an
          # explicit guard the unsupported_inbox_provider check would let it through and
          # persist a Disparo with zero inboxes — a draft that can never run (the audience
          # filter requires an inbox and there is no update action to add one later).
          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('invalid_audience_filter')
        end

        it 'rejects absent inbox_ids with a 422 and persists nothing (no un-runnable draft)' do
          params = valid_params.deep_dup
          params[:disparo].delete(:inbox_ids)

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('invalid_audience_filter')
        end

        it 'treats a WhatsApp inbox with a missing channel as non-Cloud without raising (nil-safe guard)' do
          # Orphaned polymorphic association: the channel row is gone but the inbox row
          # survives (channel_type stays 'Channel::Whatsapp', so whatsapp? is true while
          # channel is nil). The cloud predicate must not call provider on nil — it would
          # 500 instead of cleanly rejecting the unsupported inbox.
          channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                              sync_templates: false, validate_provider_config: false)
          orphaned_inbox = channel.inbox
          Channel::Whatsapp.where(id: channel.id).delete_all
          params = valid_params.deep_dup
          params[:disparo][:inbox_ids] = [orphaned_inbox.id]

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.to not_change(Disparo, :count).and not_change(DisparoInbox, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('unsupported_inbox_provider')
        end

        it 'returns 422 when name is missing' do
          params = valid_params.deep_dup
          params[:disparo].delete(:name)

          expect do
            post "/api/v1/accounts/#{account.id}/disparos",
                 headers: admin.create_new_auth_token, params: params, as: :json
          end.not_to change(Disparo, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'when the flag is off' do
      before { stub_beta0_flag(false) }

      it 'returns 404 and does not create anything' do
        expect do
          post "/api/v1/accounts/#{account.id}/disparos",
               headers: admin.create_new_auth_token, params: valid_params, as: :json
        end.not_to change(Disparo, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/disparos/:id' do
    let!(:disparo) { create(:disparo, account: account) }

    context 'when the flag is on' do
      before { stub_beta0_flag(true) }

      it 'returns unauthorized for an unauthenticated user' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns the disparo for an authenticated user' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(disparo.id)
      end

      it 'returns 404 when reading a disparo from another account (cross-account isolation)' do
        other_account = create(:account)
        other_disparo = create(:disparo, account: other_account)

        get "/api/v1/accounts/#{account.id}/disparos/#{other_disparo.id}",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the flag is off' do
      before { stub_beta0_flag(false) }

      it 'returns 404' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/disparos/:id/dry_run' do
    let!(:disparo) do
      create(:disparo, account: account, template_name: 'sample_shipping_confirmation', audience_filter: { 'label' => ['vip'] })
    end

    before { create(:disparo_inbox, disparo: disparo, inbox: inbox) }

    context 'when the flag is on' do
      before { stub_beta0_flag(true) }

      it 'returns the summary and never creates messages, conversations or targets' do
        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/dry_run",
               headers: admin.create_new_auth_token, as: :json
        end.to not_change(Message, :count)
          .and not_change(Conversation, :count)
          .and not_change(DisparoTarget, :count)
          .and change(DisparoAudienceSnapshot, :count).by(1) # the single allowed write

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body).to include('total_eligible', 'total_skipped', 'by_skip_reason', 'by_inbox', 'estimated_cost_cents')
        expect(body['total_eligible']).to eq(0)
        # GAP B: the FE needs the snapshot id to approve it back into shadow_run.
        expect(body['snapshot_id']).to eq(DisparoAudienceSnapshot.last.id)
      end

      it 'returns 422 with the error message when the dry-run is invalid' do
        bad = create(:disparo, account: account, template_name: nil, audience_filter: { 'label' => ['vip'] })
        create(:disparo_inbox, disparo: bad, inbox: inbox)

        post "/api/v1/accounts/#{account.id}/disparos/#{bad.id}/dry_run",
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_dry_run')
      end

      it 'returns unauthorized for an unauthenticated user' do
        post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/dry_run"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 404 for a disparo from another account (cross-account isolation)' do
        other_disparo = create(:disparo, account: create(:account))

        post "/api/v1/accounts/#{account.id}/disparos/#{other_disparo.id}/dry_run",
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the flag is off' do
      before { stub_beta0_flag(false) }

      it 'returns 404' do
        post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/dry_run",
             headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/disparos/:id/shadow_run' do
    # A real, resolvable audience so the run actually creates targets (an empty
    # audience would make the creation/idempotency asserts vacuously green).
    let(:cloud_channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    end
    let(:cloud_inbox) { cloud_channel.inbox }
    let(:filter) { { 'kanban_steps' => %w[3], 'label' => ['vip'] } }
    let!(:disparo) do
      disparo = create(:disparo, account: account, template_name: 'sample_shipping_confirmation', audience_filter: filter)
      create(:disparo_inbox, disparo: disparo, inbox: cloud_inbox)
      disparo
    end

    before do
      eligible_contact = create(:contact, account: account, phone_number: '+5511999998888')
      create(:conversation, account: account, inbox: cloud_inbox, contact: eligible_contact,
                            custom_attributes: { 'kanban_step' => '3' }, label_list: ['vip'])
    end

    # GAP B: shadow_run must reference the dry-run snapshot the operator approved.
    # Run a real dry_run over HTTP and return its snapshot_id (now exposed in the
    # dry_run response) so the happy paths approve the same config they previewed.
    def approved_snapshot_id(target = disparo)
      post "/api/v1/accounts/#{account.id}/disparos/#{target.id}/dry_run",
           headers: admin.create_new_auth_token, as: :json
      response.parsed_body['snapshot_id']
    end

    context 'when the flag is on' do
      before { stub_beta0_flag(true) }

      it 'persists shadow targets without creating messages or conversations' do
        snapshot_id = approved_snapshot_id

        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, params: { snapshot_id: snapshot_id }, as: :json
        end.to not_change(Message, :count)
          .and not_change(Conversation, :count)
          .and change { DisparoTarget.where(disparo: disparo).count }.from(0).to(1)

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body).to include('total_targets' => 1, 'eligible' => 1, 'skipped' => 0, 'created' => 1, 'updated' => 0)
        expect(DisparoTarget.where(disparo: disparo)).to all(have_attributes(shadow_run: true))
      end

      it 'is idempotent over HTTP — a second call does not duplicate targets' do
        post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
             headers: admin.create_new_auth_token, params: { snapshot_id: approved_snapshot_id }, as: :json
        expect(DisparoTarget.where(disparo: disparo).count).to eq(1)

        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, params: { snapshot_id: approved_snapshot_id }, as: :json
        end.not_to(change { DisparoTarget.where(disparo: disparo).count })

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include('created' => 0, 'updated' => 1)
      end

      # GAP B load-bearing #1: no snapshot_id at all -> 422, nothing persisted.
      it 'returns 422 and persists nothing when no snapshot_id is provided' do
        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, as: :json
        end.not_to change(DisparoTarget, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_shadow_run')
      end

      it 'returns 422 when the snapshot_id does not belong to this disparo' do
        other_disparo = create(:disparo, account: account, template_name: 'sample_shipping_confirmation', audience_filter: filter)
        create(:disparo_inbox, disparo: other_disparo, inbox: cloud_inbox)
        foreign_snapshot_id = approved_snapshot_id(other_disparo)

        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, params: { snapshot_id: foreign_snapshot_id }, as: :json
        end.not_to change(DisparoTarget, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_shadow_run')
      end

      # GAP B load-bearing #2: an EXPIRED snapshot -> 422, nothing persisted.
      it 'returns 422 and persists nothing when the snapshot has expired' do
        snapshot_id = approved_snapshot_id
        DisparoAudienceSnapshot.find(snapshot_id).update!(expires_at: 1.hour.ago)

        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, params: { snapshot_id: snapshot_id }, as: :json
        end.not_to change(DisparoTarget, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_shadow_run')
      end

      # GAP B load-bearing #3 (THE load-bearing test): config changed after the
      # dry-run -> fingerprint mismatch -> 422, nothing persisted.
      it 'returns 422 and persists nothing when the config changed after the dry-run' do
        snapshot_id = approved_snapshot_id
        disparo.update!(template_category: :marketing) # config drift vs the snapshot

        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, params: { snapshot_id: snapshot_id }, as: :json
        end.not_to change(DisparoTarget, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('invalid_shadow_run')
      end

      it 'returns unauthorized for an unauthenticated user' do
        post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 404 for a disparo from another account (cross-account isolation)' do
        other_disparo = create(:disparo, account: create(:account))

        post "/api/v1/accounts/#{account.id}/disparos/#{other_disparo.id}/shadow_run",
             headers: admin.create_new_auth_token, params: { snapshot_id: 'whatever' }, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the flag is off' do
      before { stub_beta0_flag(false) }

      it 'returns 404 and creates nothing' do
        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run",
               headers: admin.create_new_auth_token, params: { snapshot_id: 'whatever' }, as: :json
        end.not_to change(DisparoTarget, :count)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/disparos/:id/targets' do
    let!(:disparo) { create(:disparo, account: account) }

    context 'when the flag is on' do
      before { stub_beta0_flag(true) }

      it 'returns the persisted targets ordered by id and never exposes the raw phone' do
        target = create(:disparo_target, disparo: disparo, state: :queued, shadow_run: true, phone_present: true)

        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.size).to eq(1)
        row = body.first
        expect(row['id']).to eq(target.id)
        expect(row['state']).to eq('queued')
        expect(row['shadow_run']).to be(true)
        # PII guard: the raw phone must never leak; only its presence does.
        expect(row).not_to have_key('phone')
        expect(row['phone_present']).to be(true)
      end

      it 'orders targets deterministically by id' do
        first = create(:disparo_target, disparo: disparo)
        second = create(:disparo_target, disparo: disparo)

        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets",
            headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body.map { |row| row['id'] }).to eq([first.id, second.id])
      end

      # Locks the documented cap (TARGETS_PER_PAGE = 50) and the order(:id) contract
      # across pages. Each :disparo_target builds a fresh conversation/contact, so the
      # 51 rows are distinct grains under the unique (disparo_id, conversation_id,
      # contact_id) index. Deleting `.per(...)` (an unbounded dump) would fail page 1.
      context 'when the audience exceeds one page' do
        let!(:target_ids) { create_list(:disparo_target, 51, disparo: disparo).map(&:id).sort }

        it 'caps the first page at TARGETS_PER_PAGE rows ordered by id' do
          get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets",
              headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          ids = response.parsed_body.map { |row| row['id'] }
          expect(ids.size).to eq(50)
          expect(ids).to eq(target_ids.first(50))
        end

        it 'returns the remaining row on page 2 with no overlap or gap' do
          get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets?page=2",
              headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          ids = response.parsed_body.map { |row| row['id'] }
          expect(ids).to eq([target_ids.last])
        end
      end

      it 'returns unauthorized for an unauthenticated user' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 404 for a disparo from another account (cross-account isolation)' do
        other_disparo = create(:disparo, account: create(:account))

        get "/api/v1/accounts/#{account.id}/disparos/#{other_disparo.id}/targets",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the flag is off' do
      before { stub_beta0_flag(false) }

      it 'returns 404' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/disparos' do
    context 'when the flag is on' do
      before { stub_beta0_flag(true) }

      it 'returns unauthorized for an unauthenticated user' do
        get "/api/v1/accounts/#{account.id}/disparos"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'lists only the current account disparos (cross-account isolation)' do
        own = create(:disparo, account: account)
        other = create(:disparo, account: create(:account))

        get "/api/v1/accounts/#{account.id}/disparos",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body.map { |row| row['id'] }
        expect(ids).to include(own.id)
        expect(ids).not_to include(other.id)
      end

      # The index eager-loads :disparo_inboxes (the _disparo partial reads inbox_ids
      # off the association per row). Locks the rendered inbox_ids so the eager-load
      # cannot silently drop or reorder the linked inboxes.
      it 'renders inbox_ids for each listed disparo from the eager-loaded association' do
        disparo = create(:disparo, account: account)
        first_inbox = create(:disparo_inbox, disparo: disparo).inbox
        second_inbox = create(:disparo_inbox, disparo: disparo).inbox

        get "/api/v1/accounts/#{account.id}/disparos",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        row = response.parsed_body.find { |r| r['id'] == disparo.id }
        expect(row['inbox_ids']).to contain_exactly(first_inbox.id, second_inbox.id)
      end

      # Locks the documented cap (DISPAROS_PER_PAGE = 25) and the deterministic
      # order(created_at: :desc, id: :desc) across pages. id is monotonic with
      # insertion, so the order collapses to id descending; cap+1 rows split as
      # 25 on page 1 and the remainder on page 2 with no overlap or gap.
      context 'when the account has more disparos than one page' do
        let!(:disparo_ids) { create_list(:disparo, 26, account: account).map(&:id).sort.reverse }

        it 'caps the first page at DISPAROS_PER_PAGE rows ordered created_at desc, id desc' do
          get "/api/v1/accounts/#{account.id}/disparos",
              headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          ids = response.parsed_body.map { |row| row['id'] }
          expect(ids.size).to eq(25)
          expect(ids).to eq(disparo_ids.first(25))
        end

        it 'returns the remaining row on page 2 with no overlap or gap' do
          get "/api/v1/accounts/#{account.id}/disparos?page=2",
              headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          ids = response.parsed_body.map { |row| row['id'] }
          expect(ids).to eq([disparo_ids.last])
        end
      end
    end

    context 'when the flag is off' do
      before { stub_beta0_flag(false) }

      it 'returns 404' do
        create(:disparo, account: account)

        get "/api/v1/accounts/#{account.id}/disparos",
            headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # DisparoPolicy is admin-only: every endpoint authorizes @account_user.administrator?
  # (mirroring InboxPolicy#submit_template?). account_user.role is an exclusive enum
  # (agent | administrator), so a non-admin agent must be rejected everywhere. The
  # visibility flag is ON here so the request reaches the authorization layer (a
  # flag-off 404 would mask the 403 and test the wrong thing).
  describe 'authorization is admin-only' do
    before { stub_beta0_flag(true) }

    context 'when it is an authenticated agent (non-admin)' do
      let!(:disparo) { create(:disparo, account: account) }

      before { create(:disparo_inbox, disparo: disparo, inbox: inbox) }

      it 'returns unauthorized on index' do
        get "/api/v1/accounts/#{account.id}/disparos", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized on show' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized on create and persists nothing' do
        params = { disparo: { name: 'Reativação', template_name: 'welcome_back', inbox_ids: [inbox.id] } }

        expect do
          post "/api/v1/accounts/#{account.id}/disparos", headers: agent.create_new_auth_token, params: params, as: :json
        end.not_to change(Disparo, :count)

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized on dry_run' do
        post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/dry_run", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized on shadow_run and persists no targets' do
        expect do
          post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/shadow_run", headers: agent.create_new_auth_token, as: :json
        end.not_to change(DisparoTarget, :count)

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized on targets' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      let!(:disparo) { create(:disparo, account: account) }

      it 'authorizes index' do
        get "/api/v1/accounts/#{account.id}/disparos", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'authorizes show' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'authorizes targets' do
        get "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/targets", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  # AC10: there is no dispatch/send surface in Beta 0; the route must not exist.
  describe 'dispatch route' do
    let!(:disparo) { create(:disparo, account: account) }

    it 'is not a recognized route' do
      expect do
        Rails.application.routes.recognize_path(
          "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/dispatch", method: :post
        )
      end.to raise_error(ActionController::RoutingError)
    end

    it 'responds 404 when a client posts to it' do
      post "/api/v1/accounts/#{account.id}/disparos/#{disparo.id}/dispatch",
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  # AC13: the visibility flag must NOT affect the send guard. The guard hard-raises
  # regardless of the flag value (it has no flag branch at all).
  describe 'BlockedSendGuard is independent of the visibility flag' do
    it 'raises blocked_send_beta_0 when the flag is off' do
      stub_beta0_flag(false)
      expect { Disparos::BlockedSendGuard.block! }.to raise_error(have_attributes(message: 'blocked_send_beta_0'))
    end

    it 'raises blocked_send_beta_0 when the flag is on' do
      stub_beta0_flag(true)
      expect { Disparos::BlockedSendGuard.block! }.to raise_error(have_attributes(message: 'blocked_send_beta_0'))
    end
  end
end
