require 'rails_helper'

RSpec.describe Integrations::Clickup::AddCommentJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, name: 'Fábio Rocha', email: 'fabio@auris.ia.br') }
  let(:ticket) do
    create(:ticket,
           account: account,
           user: agent,
           sync_status: :synced,
           clickup_task_id: 'CU_TASK_1')
  end
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }

  before do
    allow(Integrations::Clickup::Client).to receive(:new).and_return(client)
  end

  context 'when the ticket is synced' do
    it 'sends the operator name + email as prefix so the ops team knows who wrote the comment' do
      allow(client).to receive(:add_comment)

      described_class.new.perform(ticket.id, 'mais uma info', agent.id)

      expect(client).to have_received(:add_comment).with(
        'CU_TASK_1',
        "Fábio Rocha (fabio@auris.ia.br):\nmais uma info"
      )
    end

    it 'falls back to raw text if no author user is provided' do
      allow(client).to receive(:add_comment)

      described_class.new.perform(ticket.id, 'system note', nil)

      expect(client).to have_received(:add_comment).with('CU_TASK_1', 'system note')
    end
  end

  it 'is a no-op when the ticket has not synced yet — comments would 404 on ClickUp' do
    ticket.update!(sync_status: :pending_sync, clickup_task_id: nil)
    allow(client).to receive(:add_comment)

    described_class.new.perform(ticket.id, 'hi', agent.id)

    expect(client).not_to have_received(:add_comment)
  end

  it 'is a no-op on a deleted ticket' do
    ticket_id = ticket.id
    ticket.destroy!
    expect { described_class.new.perform(ticket_id, 'hi', agent.id) }.not_to raise_error
  end

  it 'skips blank comments (defense in depth — the controller already blocks them)' do
    allow(client).to receive(:add_comment)

    described_class.new.perform(ticket.id, '', agent.id)

    expect(client).not_to have_received(:add_comment)
  end

  context 'when ClickUp is transiently unavailable' do
    before do
      allow(client).to receive(:add_comment).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'timeout')
    end

    it 'reschedules with a longer backoff on subsequent failures' do
      expect do
        described_class.new.perform(ticket.id, 'hi', agent.id, 0)
      end.to have_enqueued_job(described_class).with(ticket.id, 'hi', agent.id, 1)
    end

    it 'gives up after MAX_ATTEMPTS' do
      expect do
        described_class.new.perform(ticket.id, 'hi', agent.id, described_class::MAX_ATTEMPTS - 1)
      end.not_to have_enqueued_job(described_class)
    end
  end

  context 'when ClickUp rejects credentials' do
    it 'logs and stops — auth errors are terminal' do
      allow(client).to receive(:add_comment).and_raise(Integrations::Clickup::Client::Unauthorized, '401')

      expect do
        described_class.new.perform(ticket.id, 'hi', agent.id, 0)
      end.not_to have_enqueued_job(described_class)
    end
  end
end
