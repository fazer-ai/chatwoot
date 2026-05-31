require 'rails_helper'

describe Disparos::ShadowRunService do
  # GAP B: a shadow run must reference an approved, unexpired dry-run snapshot
  # whose config fingerprint matches the disparo's CURRENT config. `run` captures
  # a fresh valid snapshot for the disparo's current config and performs against
  # it; the per-snapshot specs at the bottom exercise the gate directly. The
  # not-runnable specs use `service` (no snapshot) because validate_runnable! runs
  # before the snapshot gate.
  subject(:service) { described_class.new(now: now) }

  # Build a valid snapshot for `d`'s CURRENT config (via DryRunService, which
  # writes the correct fingerprint + TTL) and perform the shadow run with it.
  def run(disparo_to_run = disparo)
    described_class.new(now: now, snapshot_id: valid_snapshot(disparo_to_run).id).perform(disparo_to_run)
  end

  # A fresh, fingerprint-matched, unexpired snapshot for the disparo's CURRENT
  # config. Used when the run must be invoked manually (e.g. inside an explicit
  # outer transaction) instead of via the `run` helper.
  def valid_snapshot(disparo_to_run = disparo)
    Disparos::DryRunService.new(now: now).perform(disparo_to_run).snapshot
  end

  let(:account) { create(:account) }
  let(:cloud_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:cloud_inbox) { cloud_channel.inbox }
  # The factory's default message_templates approve this name (status 'approved'),
  # so every factory-built cloud inbox is on the per-template allowlist (G4).
  let(:template_name) { 'sample_shipping_confirmation' }
  let(:now) { Time.zone.parse('2026-05-29 12:00:00') }
  let(:filter) { { 'kanban_steps' => %w[3], 'label' => ['vip'] } }

  let(:disparo) do
    disparo = create(:disparo, account: account, template_name: template_name, audience_filter: filter)
    create(:disparo_inbox, disparo: disparo, inbox: cloud_inbox)
    disparo
  end

  # Candidate matching the filter (Stage 3 + label vip) on the cloud inbox.
  def candidate(custom_attributes: {}, contact: nil, label_list: ['vip'])
    attrs = custom_attributes.merge('kanban_step' => '3')
    convo_attrs = { account: account, inbox: cloud_inbox, custom_attributes: attrs, label_list: label_list }
    convo_attrs[:contact] = contact if contact
    create(:conversation, **convo_attrs)
  end

  describe '#perform' do
    context 'when the disparo is not runnable for shadow-run' do
      it 'raises InvalidShadowRun when template_name is blank' do
        disparo.update!(template_name: nil)

        expect { service.perform(disparo) }.to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
      end

      it 'raises InvalidShadowRun when there is no disparo_inbox' do
        bare = create(:disparo, account: account, template_name: template_name, audience_filter: filter)

        expect { service.perform(bare) }.to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
      end

      it 'raises InvalidShadowRun when the audience filter has neither kanban_steps nor label' do
        disparo.update!(audience_filter: {})

        expect { service.perform(disparo) }.to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
      end
    end

    context 'with a kanban_step + label filter (AC7)' do
      it 'persists BOTH eligible (queued) and skipped targets plus their events', :aggregate_failures do
        eligible_contact = create(:contact, account: account, phone_number: '+5511999998888')
        candidate(contact: eligible_contact)
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        skipped_convo = candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        summary = run(disparo)

        expect(summary.total_targets).to eq(2)
        expect(summary.eligible).to eq(1)
        expect(summary.skipped).to eq(1)
        expect(summary.created).to eq(2)
        expect(summary.updated).to eq(0)

        expect(DisparoTarget.where(disparo: disparo).count).to eq(2)
        expect(DisparoEvent.count).to eq(2)

        skipped_target = DisparoTarget.find_by(disparo: disparo, conversation_id: skipped_convo.id)
        expect(skipped_target.state).to eq('skipped')
        expect(skipped_target.primary_skip_reason).to eq('opt_out_lgpd')
        expect(skipped_target.skip_reasons).to eq(['opt_out_lgpd'])
        expect(DisparoEvent.find_by(disparo_target: skipped_target).event_type).to eq('skipped')
        expect(DisparoEvent.find_by(disparo_target: skipped_target).payload).to eq(
          'primary_skip_reason' => 'opt_out_lgpd', 'skip_reasons' => ['opt_out_lgpd']
        )
      end

      it 'maps an eligible candidate to a queued target with no skip reasons and a queued event' do
        eligible_contact = create(:contact, account: account, phone_number: '+5511999998888')
        eligible_convo = candidate(contact: eligible_contact)

        run(disparo)

        target = DisparoTarget.find_by(disparo: disparo, conversation_id: eligible_convo.id)
        expect(target.state).to eq('queued')
        expect(target.primary_skip_reason).to be_nil
        expect(target.skip_reasons).to eq([])
        expect(target.contact_id).to eq(eligible_contact.id)
        expect(target.inbox_id).to eq(cloud_inbox.id)
        expect(target.phone_present).to be(true)
        expect(DisparoEvent.find_by(disparo_target: target).event_type).to eq('queued')
      end
    end

    # wf15 reconciliation: the audience is scoped to the disparo's SELECTED
    # inboxes. A matching candidate on an unselected cloud inbox never becomes a
    # target (absent from the audience, not persisted as skipped).
    context 'when a matching candidate is on a cloud inbox the disparo did NOT select' do
      it 'never persists a target for it', :aggregate_failures do
        other_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false).inbox
        selected_convo = candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        unselected_convo = create(:conversation, account: account, inbox: other_inbox,
                                                 custom_attributes: { 'kanban_step' => '3' }, label_list: ['vip'],
                                                 contact: create(:contact, account: account, phone_number: '+5511999990002'))

        summary = run(disparo)

        expect(summary.total_targets).to eq(1)
        expect(DisparoTarget.find_by(disparo: disparo, conversation_id: selected_convo.id)).to be_present
        expect(DisparoTarget.find_by(disparo: disparo, conversation_id: unselected_convo.id)).to be_nil
      end
    end

    # wf15 reconciliation: the disparo's conversation_status gates the audience.
    context 'with the conversation_status gate (open vs all)' do
      it "with conversation_status 'open' never persists a target for a resolved candidate", :aggregate_failures do
        open_convo = candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        resolved_convo = candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))
        resolved_convo.update!(status: :resolved)

        summary = run(disparo) # disparo defaults conversation_status to open

        expect(summary.total_targets).to eq(1)
        expect(DisparoTarget.find_by(disparo: disparo, conversation_id: open_convo.id)).to be_present
        expect(DisparoTarget.find_by(disparo: disparo, conversation_id: resolved_convo.id)).to be_nil
      end

      it "with conversation_status 'all' persists a target for the resolved candidate too" do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        resolved_convo = candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))
        resolved_convo.update!(status: :resolved)
        disparo.update!(conversation_status: :all)

        summary = run(disparo)

        expect(summary.total_targets).to eq(2)
        expect(DisparoTarget.find_by(disparo: disparo, conversation_id: resolved_convo.id)).to be_present
      end
    end

    context 'with the shadow_run flag (AC8)' do
      it 'sets shadow_run = true on EVERY persisted target (eligible AND skipped)' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        run(disparo)

        expect(DisparoTarget.where(disparo: disparo)).to all(have_attributes(shadow_run: true))
        expect(DisparoTarget.where(disparo: disparo, shadow_run: false)).to be_empty
      end
    end

    context 'with the Phase 4 exit gate (zero Meta call, zero Chatwoot message)' do
      it 'never creates a Message or Conversation while writing shadow targets', :aggregate_failures do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        expect { run(disparo) }
          .to not_change(Message, :count)
          .and not_change(Conversation, :count)
          .and change(DisparoTarget, :count).by(2)
          .and change(DisparoEvent, :count).by(2)

        expect(DisparoTarget.where(disparo: disparo)).to all(have_attributes(shadow_run: true))
      end
    end

    context 'when re-running on the same disparo (AC46 idempotent upsert)', :aggregate_failures do
      it 'updates targets in place — no duplicate rows, counts stable, state flips queued -> skipped' do
        contact = create(:contact, account: account, phone_number: '+5511999998888')
        conversation = candidate(contact: contact)

        first = run(disparo)
        expect(first.created).to eq(1)
        target_id = DisparoTarget.find_by(disparo: disparo, conversation_id: conversation.id).id
        expect(DisparoTarget.find(target_id).state).to eq('queued')

        # Candidate turns ineligible between runs (now opted out).
        conversation.update!(custom_attributes: { 'kanban_step' => '3', 'opt_out_lgpd' => true })

        second = nil
        expect { second = run(disparo) }.not_to change(DisparoTarget, :count)

        expect(second.created).to eq(0)
        expect(second.updated).to eq(1)
        expect(DisparoTarget.where(disparo: disparo).count).to eq(1)

        reloaded = DisparoTarget.find(target_id)
        expect(reloaded.state).to eq('skipped')
        expect(reloaded.primary_skip_reason).to eq('opt_out_lgpd')
        expect(reloaded.skip_reasons).to eq(['opt_out_lgpd'])
        expect(reloaded.shadow_run).to be(true)

        # Event-append policy (a): one event on creation, one on the queued -> skipped transition.
        expect(DisparoEvent.where(disparo_target_id: target_id).count).to eq(2)
        expect(DisparoEvent.where(disparo_target_id: target_id).pluck(:event_type)).to eq(%w[queued skipped])

        # `already_in_shadow_run` is intra-run only — never persisted for the wf15 comparison.
        expect(DisparoTarget.where(disparo: disparo).pluck(:skip_reasons).flatten).not_to include('already_in_shadow_run')
        expect(DisparoTarget.where(disparo: disparo).pluck(:primary_skip_reason)).not_to include('already_in_shadow_run')
      end

      it 'does not append a new event when an unchanged candidate is re-evaluated' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))

        run(disparo)
        expect { run(disparo) }.not_to change(DisparoEvent, :count)
      end

      it 'clears stale skip data and flips skipped -> queued in place when a candidate becomes eligible (AC46)', :aggregate_failures do
        contact = create(:contact, account: account, phone_number: '+5511999998888')
        conversation = candidate(contact: contact, custom_attributes: { 'opt_out_lgpd' => true })

        first = run(disparo)
        expect(first.created).to eq(1)
        target_id = DisparoTarget.find_by(disparo: disparo, conversation_id: conversation.id).id
        skipped = DisparoTarget.find(target_id)
        expect(skipped.state).to eq('skipped')
        expect(skipped.primary_skip_reason).to eq('opt_out_lgpd')
        expect(skipped.skip_reasons).to eq(['opt_out_lgpd'])

        # Candidate becomes eligible between runs (opt-out cleared).
        conversation.update!(custom_attributes: { 'kanban_step' => '3' })

        second = nil
        expect { second = run(disparo) }.not_to change(DisparoTarget, :count)

        expect(second.created).to eq(0)
        expect(second.updated).to eq(1)
        expect(DisparoTarget.where(disparo: disparo).count).to eq(1)

        reloaded = DisparoTarget.find(target_id)
        expect(reloaded.state).to eq('queued')
        expect(reloaded.primary_skip_reason).to be_nil
        expect(reloaded.skip_reasons).to eq([])
        expect(reloaded.shadow_run).to be(true)

        # Event-append policy: one event on creation (skipped), one on the skipped -> queued transition.
        expect(DisparoEvent.where(disparo_target_id: target_id).pluck(:event_type)).to eq(%w[skipped queued])
      end
    end

    context 'with run-level observability (US20: ids + counts only, no PII)', :aggregate_failures do
      it 'emits shadow_run_started + shadow_run_completed with safe payload keys (no phone/hmac/token)' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        # Snapshot OUTSIDE the subscribed block so dry_run's own notifications do
        # not leak into the captured shadow_run stream.
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        captured = []
        ActiveSupport::Notifications.subscribed(
          ->(name, _start, _finish, _id, payload) { captured << [name, payload] }, /\Adisparos\.shadow_run_/
        ) { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }

        names = captured.map(&:first)
        expect(names).to eq(%w[disparos.shadow_run_started disparos.shadow_run_completed])

        started_payload = captured.find { |name, _| name == 'disparos.shadow_run_started' }.last
        completed_payload = captured.find { |name, _| name == 'disparos.shadow_run_completed' }.last

        expect(started_payload.keys).to contain_exactly(:disparo_id)
        expect(started_payload[:disparo_id]).to eq(disparo.id)

        # Exact key set proves the safe keys AND that no phone/phone_number/hmac/token rode along.
        expect(completed_payload.keys).to contain_exactly(:disparo_id, :total_targets, :eligible, :skipped)
        expect(completed_payload[:total_targets]).to eq(2)
        expect(completed_payload[:eligible]).to eq(1)
        expect(completed_payload[:skipped]).to eq(1)
      end
    end

    context 'with per-target observability (US20: ids + skip enums only, no PII)', :aggregate_failures do
      it 'emits target_queued_shadow + target_skipped with safe payload keys (no phone/phone_present/hmac/token)' do
        eligible_contact = create(:contact, account: account, phone_number: '+5511999998888')
        eligible_convo = candidate(contact: eligible_contact)
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        skipped_convo = candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        captured = []
        ActiveSupport::Notifications.subscribed(
          ->(name, _start, _finish, _id, payload) { captured << [name, payload] }, /\Adisparos\.target_/
        ) { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }

        names = captured.map(&:first)
        expect(names).to contain_exactly('disparos.target_queued_shadow', 'disparos.target_skipped')

        queued_payload = captured.find { |name, _| name == 'disparos.target_queued_shadow' }.last
        skipped_payload = captured.find { |name, _| name == 'disparos.target_skipped' }.last

        queued_target = DisparoTarget.find_by(disparo: disparo, conversation_id: eligible_convo.id)
        skipped_target = DisparoTarget.find_by(disparo: disparo, conversation_id: skipped_convo.id)

        # Exact key set proves the safe keys AND that no phone/phone_present/hmac/token rode along.
        expect(queued_payload.keys).to contain_exactly(:disparo_id, :disparo_target_id, :conversation_id)
        expect(queued_payload[:disparo_id]).to eq(disparo.id)
        expect(queued_payload[:disparo_target_id]).to eq(queued_target.id)
        expect(queued_payload[:conversation_id]).to eq(eligible_convo.id)

        expect(skipped_payload.keys).to contain_exactly(
          :disparo_id, :disparo_target_id, :conversation_id, :primary_skip_reason, :skip_reasons
        )
        expect(skipped_payload[:disparo_id]).to eq(disparo.id)
        expect(skipped_payload[:disparo_target_id]).to eq(skipped_target.id)
        expect(skipped_payload[:conversation_id]).to eq(skipped_convo.id)
        expect(skipped_payload[:primary_skip_reason]).to eq('opt_out_lgpd')
        expect(skipped_payload[:skip_reasons]).to eq(['opt_out_lgpd'])
      end
    end

    context 'when the same contact appears in two conversations (AC43)', :aggregate_failures do
      it 'persists one queued and one skipped target for the same contact across different conversations' do
        contact = create(:contact, account: account, phone_number: '+5511999998888')
        eligible_convo = candidate(contact: contact)
        skipped_convo = candidate(contact: contact, custom_attributes: { 'opt_out_lgpd' => true })

        summary = run(disparo)

        expect(summary.total_targets).to eq(2)
        expect(summary.eligible).to eq(1)
        expect(summary.skipped).to eq(1)

        targets = DisparoTarget.where(disparo: disparo)
        expect(targets.count).to eq(2)
        expect(targets.pluck(:contact_id).uniq).to eq([contact.id])
        expect(targets.pluck(:conversation_id)).to contain_exactly(eligible_convo.id, skipped_convo.id)
        expect(targets.pluck(:state)).to contain_exactly('queued', 'skipped')

        skipped_target = DisparoTarget.find_by(disparo: disparo, conversation_id: skipped_convo.id)
        expect(skipped_target.primary_skip_reason).to eq('opt_out_lgpd')
      end
    end

    # TOCTOU guard, COMMON path (ActiveRecord::RecordInvalid). AudienceResolver reads
    # the candidate set at the top of the run; migration 20260603000000 wired
    # disparo_targets to ON DELETE CASCADE FKs on conversation_id/contact_id. The
    # service builds each target from the FK INTEGER (find_or_initialize_by) with NO
    # cached association object, and DisparoTarget belongs_to :conversation/:contact
    # are REQUIRED. So when a candidate's conversation is deleted concurrently between
    # the audience read and the save, the required-presence validator RE-QUERIES the
    # now-missing parent and save! raises ActiveRecord::RecordInvalid ("Conversation
    # must exist") BEFORE any SQL write — this is the DOMINANT real-world error, not
    # InvalidForeignKey (which is only the rarer validation-SELECT↔INSERT race, spec
    # below). The rescue must catch RecordInvalid too, or the run 500s. The narrowed
    # rescue drops ONLY the candidate whose own parent actually vanished.
    #
    # FAITHFUL: this runs perform INSIDE an outer transaction (mimicking the
    # controller's `@disparo.with_lock`) and triggers a GENUINE RecordInvalid via a
    # real concurrent delete + real save!, NOT a stubbed raise. The delete is fired
    # from the `state_changed?` hook (the call immediately before the save) so it
    # lands in the OUTER transaction and the real save! then fails validation.
    context 'when THIS candidate vanishes mid-run inside the controller transaction (TOCTOU, RecordInvalid path)', :aggregate_failures do
      it 'drops the vanished candidate, does not raise, and persists only the survivor' do
        doomed = candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))
        # Capture the approval snapshot BEFORE the stub is armed (DryRunService does not
        # persist targets, so it never trips the state_changed? hook).
        snapshot = valid_snapshot

        # Real concurrent delete fired from the call immediately before save!. No save!
        # stub: the REAL save! re-queries the missing parent and raises a GENUINE
        # ActiveRecord::RecordInvalid. Branch on the receiver's conversation_id
        # (AudienceResolver order is not guaranteed).
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(DisparoTarget).to receive(:state_changed?).and_wrap_original do |original|
          Conversation.where(id: doomed.id).delete_all if original.receiver.conversation_id == doomed.id
          original.call
        end
        # rubocop:enable RSpec/AnyInstance

        summary = nil
        # Mimic the controller's `@disparo.with_lock`: run the whole perform inside an
        # OPEN transaction. Even the RecordInvalid path must not escape and 500 the run.
        expect do
          ActiveRecord::Base.transaction { summary = described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
        end.not_to raise_error

        # Only the surviving target is counted and persisted; the dropped one leaves no
        # row — proving the outer transaction stayed USABLE after the failure.
        expect(summary.total_targets).to eq(1)
        expect(summary.eligible).to eq(1)
        expect(summary.skipped).to eq(0)
        expect(summary.created).to eq(1)
        survivor = DisparoTarget.where(disparo: disparo)
        expect(survivor.count).to eq(1)
        expect(survivor.first.conversation_id).not_to eq(doomed.id)
        # The dropped candidate gets NO event; exactly one event for the survivor.
        expect(DisparoEvent.count).to eq(1)
      end
    end

    # TOCTOU guard, RARE INSERT-level race (ActiveRecord::InvalidForeignKey). If the
    # parent vanishes in the nanosecond gap BETWEEN the presence-validation SELECT and
    # the INSERT, validation passes but the DB FK fires — a real failing write that
    # ABORTS the controller's surrounding `@disparo.with_lock` transaction. This is the
    # exact case the SAVEPOINT (requires_new: true) protects: without it, the aborted
    # outer transaction poisons the narrowed rescue's existence probes
    # (PG::InFailedSqlTransaction) and the run still 500s.
    #
    # We reproduce the race DETERMINISTICALLY by priming the association cache so the
    # presence validator passes WITHOUT re-querying, THEN deleting the row so the real
    # INSERT FK-violates. This is the red-green spec for the savepoint: revert the
    # savepoint (plain `target.save!`) and this fails with PG::InFailedSqlTransaction;
    # restore it and it is green.
    context 'when the parent vanishes between validation and INSERT (TOCTOU, InvalidForeignKey race)', :aggregate_failures do
      it 'isolates the FK abort in a savepoint, does not raise, and persists only the survivor' do
        doomed = candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        doomed_convo = Conversation.find(doomed.id) # capture the live record to prime the cache
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))
        snapshot = valid_snapshot

        # Prime the association cache (validation passes without re-query) then delete the
        # row, OUTSIDE the savepoint, from the call immediately before save!. The REAL
        # INSERT then fires a GENUINE ActiveRecord::InvalidForeignKey — a failing write
        # that aborts the outer transaction unless the savepoint isolates it.
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(DisparoTarget).to receive(:state_changed?).and_wrap_original do |original|
          receiver = original.receiver
          if receiver.conversation_id == doomed.id
            receiver.conversation = doomed_convo
            receiver.contact = doomed_convo.contact
            Conversation.where(id: doomed.id).delete_all
          end
          original.call
        end
        # rubocop:enable RSpec/AnyInstance

        summary = nil
        expect do
          ActiveRecord::Base.transaction { summary = described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
        end.not_to raise_error

        expect(summary.total_targets).to eq(1)
        expect(summary.eligible).to eq(1)
        expect(summary.created).to eq(1)
        survivor = DisparoTarget.where(disparo: disparo)
        expect(survivor.count).to eq(1)
        expect(survivor.first.conversation_id).not_to eq(doomed.id)
        expect(DisparoEvent.count).to eq(1)
      end
    end

    # TOCTOU guard, EVENT-WRITE isolation — the regression Codex flagged. The
    # per-candidate unit is TWO writes: the target UPSERT (save!) AND its transition
    # event (append_event -> DisparoEvent.create!). append_event runs AFTER save! but is
    # itself a DB WRITE; it MUST share the SAME savepoint as save!. If it lives OUTSIDE
    # the savepoint (the pre-fix structure), its FK failure aborts the controller's
    # surrounding `@disparo.with_lock` transaction and poisons every later query — the
    # rescue's existence probes then raise PG::InFailedSqlTransaction and the run 500s.
    #
    # FAITHFUL DETERMINISTIC TRIGGER. disparo_events.disparo_target_id is an ON DELETE
    # CASCADE FK to disparo_targets, which itself cascades from conversations
    # (20260603000000). We first run the service so BOTH candidates have a PERSISTED
    # target. Then the doomed candidate is flipped ineligible so the second run's
    # `state_changed?` is true and append_event fires (queued -> skipped). On that second
    # run, inside `state_changed?` (the call immediately BEFORE the savepoint opens) we:
    #   (a) PRIME the doomed target's conversation/contact association cache, so save!'s
    #       required-presence validator passes WITHOUT re-querying — otherwise save! would
    #       re-query the missing parent and fail as RecordInvalid BEFORE reaching the event
    #       write, masking the path under test; and
    #   (b) DELETE the doomed conversation. The delete lands in the OUTER transaction
    #       (state_changed? runs before the savepoint) so it is DURABLE across the
    #       savepoint rollback — a delete issued INSIDE the savepoint would be undone by
    #       its own rollback, hiding the race. The cascade removes the doomed target row.
    # save! is then an UPDATE matching 0 rows (no FK re-check, succeeds), so the FAILURE
    # POINT is append_event: the REAL DisparoEvent.create! fires a GENUINE
    # ActiveRecord::InvalidForeignKey on the vanished disparo_target_id — not a stubbed
    # raise. This isolates the EVENT write specifically: save! does NOT fail here, only
    # append_event's placement is under test.
    #
    # RED-GREEN (verified): with append_event OUTSIDE the savepoint (pre-fix) the FK abort
    # hits the OUTER transaction directly and the rescue's `Conversation.exists?` probe
    # raises ActiveRecord::StatementInvalid (cause: PG::InFailedSqlTransaction) — perform
    # 500s. With both writes in ONE savepoint it is green: the savepoint rolls the failed
    # event back, the outer transaction stays usable, the probe sees the doomed
    # conversation gone and DROPS the candidate, and only the survivor persists.
    context 'when the event write fails after the target committed (TOCTOU, append_event isolation)', :aggregate_failures do
      it 'isolates the event-write FK abort in the shared savepoint, does not raise, and persists only the survivor' do
        doomed = candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        doomed_convo = Conversation.find(doomed.id) # live record captured to prime the cache
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))

        # First run: BOTH candidates get a persisted target (doomed currently queued).
        run(disparo)
        expect(DisparoTarget.where(disparo: disparo).count).to eq(2)

        # Flip the doomed candidate ineligible so the 2nd run's state_changed? is true and
        # append_event fires (queued -> skipped transition).
        Conversation.find(doomed.id).update!(custom_attributes: { 'kanban_step' => '3', 'opt_out_lgpd' => true })
        snapshot = valid_snapshot

        # On the 2nd run, from state_changed? (OUTSIDE the savepoint): prime the cache so
        # save! validates as an UPDATE, then DURABLY delete the doomed conversation. The
        # cascade removes the doomed target row; save! (UPDATE, 0 rows) succeeds, and
        # append_event's DisparoEvent.create! fires a GENUINE InvalidForeignKey on the
        # now-missing disparo_target_id.
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(DisparoTarget).to receive(:state_changed?).and_wrap_original do |original|
          receiver = original.receiver
          if receiver.conversation_id == doomed.id
            receiver.conversation = doomed_convo
            receiver.contact = doomed_convo.contact
            Conversation.where(id: doomed.id).delete_all
          end
          original.call
        end
        # rubocop:enable RSpec/AnyInstance

        summary = nil
        # Mimic the controller's `@disparo.with_lock`: the whole run inside an OPEN
        # transaction. The event-write FK abort must not escape and 500 the run.
        expect do
          ActiveRecord::Base.transaction { summary = described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
        end.not_to raise_error

        # Summary reflects ONLY the survivor (the doomed candidate was dropped: no tally).
        expect(summary.total_targets).to eq(1)
        expect(summary.eligible).to eq(1)
        expect(summary.skipped).to eq(0)
        # The doomed target row is ROLLED BACK / cascade-gone -> absent; the outer txn
        # stayed usable so the survivor's row remains.
        survivor = DisparoTarget.where(disparo: disparo)
        expect(survivor.count).to eq(1)
        expect(survivor.first.conversation_id).not_to eq(doomed.id)
        expect(DisparoTarget.find_by(disparo: disparo, conversation_id: doomed.id)).to be_nil
        # No half-written event for the doomed target: the failed event rolled back with
        # its savepoint, and the cascade removed the doomed candidate's first-run event
        # alongside its target. Net: exactly the survivor's single (first-run) event.
        expect(DisparoEvent.where(disparo_target_id: survivor.first.id).count).to eq(1)
        expect(DisparoEvent.count).to eq(1)
      end
    end

    # The negative that pins Codex's P2: a FK violation while the candidate's OWN
    # conversation AND contact still exist is NOT the candidate-vanished TOCTOU — it
    # is run-wide invalid state (e.g. the disparo deleted mid-run, hitting the
    # disparo_id FK). The narrowed rescue MUST re-raise it instead of masking the run
    # as a successful/partial completion. With the broad rescue this swallows; with
    # the narrowed guard perform re-raises — a genuine red-green guard.
    context 'when an FK violation fires while both parents still exist (run-wide invalid state)', :aggregate_failures do
      it 're-raises InvalidForeignKey instead of masking the run as complete' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))

        # Raise the FK violation WITHOUT deleting the conversation/contact: both of the
        # candidate's parents still exist, so the rescue's existence check holds and the
        # violation re-raises (it was not this candidate vanishing).
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(DisparoTarget).to receive(:save!)
          .and_raise(ActiveRecord::InvalidForeignKey, 'run-wide FK violation (e.g. disparo deleted mid-run)')
        # rubocop:enable RSpec/AnyInstance

        expect { run(disparo) }.to raise_error(ActiveRecord::InvalidForeignKey)
        # Nothing was masked into a successful/partial summary; the run aborted.
        expect(DisparoTarget.where(disparo: disparo).count).to eq(0)
      end
    end

    # GAP B: the shadow run may only persist the set approved in a dry-run preview.
    # These 4 exercise the snapshot gate directly at the service level: the run
    # must raise InvalidShadowRun (and persist nothing) unless the snapshot is
    # present, owned by this disparo, unexpired, and fingerprint-matched.
    context 'with the approved-snapshot gate (GAP B)' do
      before { candidate(contact: create(:contact, account: account, phone_number: '+5511999998888')) }

      # (1) no valid snapshot_id -> raise, nothing persisted.
      it 'raises InvalidShadowRun and persists nothing without a snapshot_id' do
        expect { described_class.new(now: now).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
          .and not_change(DisparoTarget, :count)
      end

      it 'raises InvalidShadowRun when the snapshot belongs to a different disparo' do
        other = create(:disparo, account: account, template_name: template_name, audience_filter: filter)
        create(:disparo_inbox, disparo: other, inbox: cloud_inbox)
        foreign = Disparos::DryRunService.new(now: now).perform(other).snapshot

        expect { described_class.new(now: now, snapshot_id: foreign.id).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
          .and(not_change { DisparoTarget.where(disparo: disparo).count })
      end

      # (2) EXPIRED snapshot -> raise, nothing persisted.
      it 'raises InvalidShadowRun and persists nothing when the snapshot is expired' do
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        snapshot.update!(expires_at: now - 1.minute)

        expect { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
          .and(not_change { DisparoTarget.where(disparo: disparo).count })
      end

      # (3) THE load-bearing test: config changed after the dry-run -> fingerprint
      # mismatch -> raise, nothing persisted. Each config dimension drifts the hash.
      it 'raises InvalidShadowRun and persists nothing when the config changed after the dry-run' do
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        disparo.update!(template_category: :marketing)

        expect { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
          .and(not_change { DisparoTarget.where(disparo: disparo).count })
      end

      it 'raises InvalidShadowRun when the audience filter changed after the dry-run' do
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        disparo.update!(audience_filter: { 'kanban_steps' => %w[3], 'label' => %w[gold] })

        expect { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
      end

      it 'raises InvalidShadowRun when the selected inbox set changed after the dry-run' do
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        second_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                 sync_templates: false, validate_provider_config: false).inbox
        create(:disparo_inbox, disparo: disparo, inbox: second_inbox)

        expect { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
      end

      # FIX 1 — the discriminating spec for gap B's account-settings vector. The
      # fingerprint now folds in the resolved per-account RulesConfig bindings, so
      # changing one binding (here dedup_window_days) after the dry-run drifts the
      # hash. Mutate through `disparo.account` (the memoized instance the run
      # resolves), not the `account` let, so the disparo sees the new settings.
      it 'raises InvalidShadowRun and persists nothing when an account rule binding changed after the dry-run' do
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot
        disparo.account.update!(
          settings: disparo.account.settings.merge('disparador_settings' => { 'dedup_window_days' => 14 })
        )

        expect { described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to raise_error(CustomExceptions::Disparos::InvalidShadowRun)
          .and(not_change { DisparoTarget.where(disparo: disparo).count })
      end

      # Unchanged settings (even a NON-default binding) -> valid flow still passes
      # and persists. This also guards the Duration-as-Integer determinism: an
      # unstable hash would mismatch dry-run vs shadow-run and wrongly raise here.
      it 'runs and persists targets when a non-default account rule binding is set but unchanged through the run' do
        disparo.account.update!(
          settings: disparo.account.settings.merge('disparador_settings' => { 'dedup_window_days' => 14 })
        )
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot

        summary = nil
        expect { summary = described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to change { DisparoTarget.where(disparo: disparo).count }.from(0).to(1)

        expect(summary.total_targets).to eq(1)
        expect(summary.eligible).to eq(1)
      end

      # (4) valid flow: dry_run -> shadow_run with the fresh snapshot -> passes + persists.
      it 'runs and persists targets with a fresh, matching, unexpired snapshot' do
        snapshot = Disparos::DryRunService.new(now: now).perform(disparo).snapshot

        summary = nil
        expect { summary = described_class.new(now: now, snapshot_id: snapshot.id).perform(disparo) }
          .to change { DisparoTarget.where(disparo: disparo).count }.from(0).to(1)

        expect(summary.total_targets).to eq(1)
        expect(summary.eligible).to eq(1)
      end
    end
  end
end
