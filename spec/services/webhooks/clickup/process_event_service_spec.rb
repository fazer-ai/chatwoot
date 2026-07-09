require 'rails_helper'

RSpec.describe Webhooks::Clickup::ProcessEventService do
  let(:account) { create(:account) }
  let!(:ticket) do
    create(
      :ticket,
      account: account,
      clickup_task_id: 'CU_TASK_1',
      clickup_status_id: 'sc_open',
      clickup_status_name: 'aberto',
      sync_status: :synced
    )
  end

  it 'mirrors a status transition onto the ticket' do
    described_class.new(
      event: 'taskStatusUpdated',
      task_id: 'CU_TASK_1',
      history_items: [
        { field: 'status', after: { id: 'sc_review', status: 'em análise', type: 'custom' } }
      ]
    ).perform

    ticket.reload
    expect(ticket.clickup_status_id).to eq('sc_review')
    expect(ticket.clickup_status_name).to eq('em análise')
  end

  it 'is a no-op when the status id has not actually changed (dedup of retried webhooks)' do
    expect do
      described_class.new(
        event: 'taskStatusUpdated',
        task_id: 'CU_TASK_1',
        history_items: [
          { field: 'status', after: { id: ticket.clickup_status_id, status: ticket.clickup_status_name } }
        ]
      ).perform
    end.not_to(change { ticket.reload.updated_at })
  end

  it 'ignores events for an unknown task id (event fired for a task not from this fork)' do
    expect do
      described_class.new(event: 'taskStatusUpdated', task_id: 'not-ours', history_items: []).perform
    end.not_to raise_error
  end

  describe 'taskCustomFieldUpdated' do
    let(:resposta_field_id) { Integrations::Clickup::FieldMap::FIELDS[:resposta_para_cliente] }

    it 'copies the new "Resposta para o Cliente" value onto the ticket' do
      described_class.new(
        event: 'taskCustomFieldUpdated',
        task_id: 'CU_TASK_1',
        history_items: [
          { field: 'custom_field',
            custom_field: { id: resposta_field_id },
            after: { value: 'Solucionado — reiniciar o navegador' } }
        ]
      ).perform

      expect(ticket.reload.resposta_para_cliente).to eq('Solucionado — reiniciar o navegador')
    end

    # Guard: taskCustomFieldUpdated fires for every custom field change on the
    # task (Ambiente, Canal, Chat ID, etc). We only sync the one field the
    # operator sees — everything else is noise and would trash the ticket's
    # local state if we mirrored it back.
    it 'is a no-op for any custom field other than "Resposta para o Cliente"' do
      described_class.new(
        event: 'taskCustomFieldUpdated',
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
end
