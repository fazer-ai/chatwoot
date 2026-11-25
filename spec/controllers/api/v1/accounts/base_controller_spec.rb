require 'rails_helper'

RSpec.describe Api::V1::Accounts::BaseController do
  describe 'callback ordering' do
    # Re-declaring `before_action :current_account` in a subclass makes Rails
    # de-duplicate the callback and move it to the end of the chain, so
    # `validate_token_api_access` runs while `Current.account` is still nil and
    # every request authenticated with the `api_access_token` header fails
    # with a 500.
    #
    # Enterprise controllers that break the order upstream, which the fork does not patch. Each one
    # must still break it: once upstream fixes it, the example fails and the entry goes.
    known_upstream_defects = {
      'Api::V1::Accounts::Captain::FaqSuggestionsController' => 'fazer-ai/chatwoot#1005'
    }

    it 'runs current_account before validate_token_api_access in every descendant' do
      Rails.application.eager_load!
      defects_seen = []

      ([described_class] + described_class.descendants).each do |controller|
        # Anonymous controllers from examples are not part of the application: RSpec names
        # them after the described class, and some deliberately invert the order to
        # reproduce a subclass defect. A real controller's name resolves to itself.
        next unless controller.name && controller.name.safe_constantize.equal?(controller)

        filters = controller._process_action_callbacks.select { |callback| callback.kind == :before }.map(&:filter)
        validate_index = filters.index(:validate_token_api_access)
        next if validate_index.nil?

        if known_upstream_defects.key?(controller.name)
          defects_seen << controller.name
          expect(filters.index(:current_account)).to be > validate_index,
                                                     "#{controller.name} is fixed upstream: drop it (#{known_upstream_defects[controller.name]})"
          next
        end

        expect(filters.index(:current_account)).to be < validate_index,
                                                   "#{controller.name} runs validate_token_api_access before current_account"
      end

      # An entry whose controller is gone, or no longer runs the check, is stale too.
      expect(defects_seen).to match_array(known_upstream_defects.keys) if ChatwootApp.enterprise?
    end
  end

  # Dois controllers anônimos, porque a ordem dos callbacks muda o que cada caminho testa:
  # com a ordem do app `current_account` roda antes e `Current.account` já existe; com a
  # ordem invertida (a de um subclass que redeclara o callback) é este check que roda
  # primeiro, com `Current.account` nil.
  describe 'com a ordem de callbacks do app' do
    controller(Api::V1::Accounts::BaseController) do
      def index
        render json: { ok: true }
      end
    end

    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    before do
      request.headers['api_access_token'] = user.access_token.token
    end

    it 'answers 401 for a suspended account' do
      account.update!(status: :suspended)

      get :index, params: { account_id: account.id }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('Account is suspended')
    end

    it 'keeps the 403 when the account is readable but API access is disabled' do
      allow(Account).to receive(:find).and_call_original
      allow(Account).to receive(:find).with(account.id.to_s).and_return(account)
      allow(account).to receive(:api_and_webhooks_enabled?).and_return(false)

      get :index, params: { account_id: account.id }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('API access is not enabled for this account')
    end

    # The previous version of this PR accepted `Current.user` as an authenticated identity
    # when `current_user` was nil. That widened who could pass the account check, so it is
    # gone: a thread-local left behind by another layer must not authenticate the request.
    it 'does not authenticate a request through a residual Current.user' do
      Current.user = create(:user, account: account)
      allow(controller).to receive(:current_user).and_return(nil)

      get :index, params: { account_id: account.id }

      expect(response).to have_http_status(:unauthorized)
    ensure
      Current.reset
    end
  end

  # Reproduz a forma de um controller cuja declaração de `current_account` foi
  # de-duplicada para o fim da cadeia: este callback roda primeiro, com
  # `Current.account` ainda nil. Chamar `api_and_webhooks_enabled?` no nil levantava
  # NoMethodError, então uma conta suspensa respondia 500 em vez de 401.
  describe 'validate_token_api_access before the account lookup' do
    controller(Api::V1::Accounts::BaseController) do
      before_action :current_account

      def index
        render json: { ok: true }
      end
    end

    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    before do
      request.headers['api_access_token'] = user.access_token.token
    end

    it 'answers 401 for a suspended account instead of raising' do
      account.update!(status: :suspended)

      get :index, params: { account_id: account.id }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('Account is suspended')
    end

    # O motivo de não bastar `return if Current.account.nil?`: com a ordem invertida o
    # lookup roda depois, então sair cedo pularia esta checagem e uma conta ativa com a
    # API desabilitada passaria. O teste roda na ordem invertida de propósito.
    it 'still answers 403 when the account is active but API access is disabled' do
      allow(Account).to receive(:find_by).and_return(account)
      allow(account).to receive(:api_and_webhooks_enabled?).and_return(false)

      get :index, params: { account_id: account.id }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('API access is not enabled for this account')
    end
  end
end
