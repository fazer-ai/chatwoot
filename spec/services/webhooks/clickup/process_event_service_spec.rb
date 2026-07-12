require 'rails_helper'

RSpec.describe Webhooks::Clickup::ProcessEventService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:ticket) do
    create(
      :ticket,
      account: account,
      user: agent,
      clickup_task_id: 'CU_TASK_1',
      clickup_status_id: 'sc_open',
      clickup_status_name: 'aberto',
      sync_status: :synced
    )
  end

  it 'mirrors a status transition onto the ticket' do
    described_class.new(
      event: 'taskUpdated',
      task_id: 'CU_TASK_1',
      history_items: [
        { field: 'status', after: { status: 'em análise', type: 'custom' } }
      ]
    ).perform

    expect(ticket.reload.clickup_status_name).to eq('em análise')
  end

  # ClickUp exposes ~7 statuses but the operator only sees 3 in Meus Tickets.
  # The service is the boundary that collapses the raw statuses down to the
  # AurisChat canonical set (Aberto / Em análise / Encerrado).
  describe 'ClickUp → AurisChat status mapping' do
    {
      'em andamento' => 'em análise',
      'aguardando informação' => 'em análise',
      'aguardando engenharia' => 'em análise',
      'bloqueado' => 'em análise',
      'descartado' => 'encerrado',
      'resolvido' => 'encerrado',
      'aberto' => 'aberto'
    }.each do |raw_clickup, expected_auris|
      it "stores '#{expected_auris}' when ClickUp sends '#{raw_clickup}'" do
        described_class.new(
          event: 'taskUpdated',
          task_id: 'CU_TASK_1',
          history_items: [
            { field: 'status', after: { status: raw_clickup, type: 'custom' } }
          ]
        ).perform

        expect(ticket.reload.clickup_status_name).to eq(expected_auris)
      end
    end

    it 'lets unknown statuses through untouched so a newly-added ClickUp option is visible instead of silently dropped' do
      described_class.new(
        event: 'taskUpdated',
        task_id: 'CU_TASK_1',
        history_items: [
          { field: 'status', after: { status: 'aguardando produto', type: 'custom' } }
        ]
      ).perform

      expect(ticket.reload.clickup_status_name).to eq('aguardando produto')
    end
  end

  # Two ClickUp raw statuses can map to the same AurisChat canonical name
  # (e.g. "em andamento" and "aguardando engenharia" both collapse to
  # "em análise"). Dedup on the canonical name skips those retransmissions
  # so the frontend doesn't wake for a change the operator can't see.
  it 'is a no-op when the mapped status has not actually changed' do
    ticket.update!(clickup_status_name: 'em análise')

    expect do
      described_class.new(
        event: 'taskUpdated',
        task_id: 'CU_TASK_1',
        history_items: [
          { field: 'status', after: { status: 'aguardando engenharia', type: 'custom' } }
        ]
      ).perform
    end.not_to(change { ticket.reload.updated_at })
  end

  it 'ignores events for an unknown task id (event fired for a task not from this fork)' do
    expect do
      described_class.new(event: 'taskUpdated', task_id: 'not-ours', history_items: []).perform
    end.not_to raise_error
  end

  describe 'taskUpdated' do
    let(:resposta_field_id) { Integrations::Clickup::FieldMap::FIELDS[:resposta_para_cliente] }

    it 'copies the new "Resposta para o Cliente" value onto the ticket' do
      described_class.new(
        event: 'taskUpdated',
        task_id: 'CU_TASK_1',
        history_items: [
          { field: 'custom_field',
            custom_field: { id: resposta_field_id },
            after: { value: 'Solucionado — reiniciar o navegador' } }
        ]
      ).perform

      expect(ticket.reload.resposta_para_cliente).to eq('Solucionado — reiniciar o navegador')
    end

    # Guard: taskUpdated fires for every custom field change on the
    # task (Ambiente, Canal, Chat ID, etc). We only sync the one field the
    # operator sees — everything else is noise and would trash the ticket's
    # local state if we mirrored it back.
    it 'is a no-op for any custom field other than "Resposta para o Cliente"' do
      described_class.new(
        event: 'taskUpdated',
        task_id: 'CU_TASK_1',
        history_items: [
          { field: 'custom_field',
            custom_field: { id: Integrations::Clickup::FieldMap::FIELDS[:chat_id] },
            after: { value: 999 } }
        ]
      ).perform

      expect(ticket.reload.resposta_para_cliente).to be_nil
    end
  end

  describe 'broadcast' do
    # Capture the enqueued job's args as a plain hash so per-field assertions
    # read off it instead of piling into a multi-line `.with do |...|` block.
    # Clears prior enqueues (factory setup fires account.cache_invalidated
    # when it creates the administrator) so we only inspect what perform! did.
    def enqueue_and_capture
      clear_enqueued_jobs
      described_class.new(**yield).perform
      job = enqueued_jobs.find { |j| j[:job] == ActionCableBroadcastJob }
      return nil if job.nil?

      tokens, event_name, payload = job[:args]
      { tokens: tokens, event: event_name, payload: payload }
    end

    # ClickUp status "Resolvido" maps to AurisChat's "Encerrado", which is
    # in the notifiable set — the operator should see a toast in Meus
    # Tickets when this fires.
    it 'broadcasts ticket.updated with notify=true when transitioning into a notifiable status' do
      broadcast = enqueue_and_capture do
        { event: 'taskUpdated',
          task_id: 'CU_TASK_1',
          history_items: [
            { field: 'status', after: { status: 'resolvido', type: 'done' } }
          ] }
      end

      expect(broadcast[:event]).to eq('ticket.updated')
      expect(broadcast[:payload].with_indifferent_access[:notify]).to be true
      expect(broadcast[:payload].with_indifferent_access[:ticket][:id]).to eq(ticket.id)
      expect(broadcast[:tokens]).to include(agent.pubsub_token, administrator.pubsub_token)
    end

    it 'broadcasts with notify=false on quiet transitions (e.g. "em análise")' do
      broadcast = enqueue_and_capture do
        { event: 'taskUpdated',
          task_id: 'CU_TASK_1',
          history_items: [
            { field: 'status', after: { status: 'em análise', type: 'custom' } }
          ] }
      end

      expect(broadcast[:event]).to eq('ticket.updated')
      expect(broadcast[:payload].with_indifferent_access[:notify]).to be false
    end

    it 'always notifies on a new "Resposta para o Cliente" so the operator sees it right away' do
      resposta_field_id = Integrations::Clickup::FieldMap::FIELDS[:resposta_para_cliente]

      broadcast = enqueue_and_capture do
        { event: 'taskUpdated',
          task_id: 'CU_TASK_1',
          history_items: [
            { field: 'custom_field',
              custom_field: { id: resposta_field_id },
              after: { value: 'Solucionado — reiniciar o navegador' } }
          ] }
      end

      expect(broadcast[:event]).to eq('ticket.updated')
      expect(broadcast[:payload].with_indifferent_access[:notify]).to be true
    end

    it 'does not broadcast when the status did not actually change' do
      expect do
        described_class.new(
          event: 'taskUpdated',
          task_id: 'CU_TASK_1',
          history_items: [
            { field: 'status', after: { status: ticket.clickup_status_name } }
          ]
        ).perform
      end.not_to have_enqueued_job(ActionCableBroadcastJob)
    end
  end
end
