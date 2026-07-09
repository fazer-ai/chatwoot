require 'rails_helper'

RSpec.describe Tickets::CreateService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:user) { create(:user, account: account) }

  let(:service) do
    described_class.new(
      user: user,
      message: message,
      params: { relatar_problema: 'IA respondeu errado', comportamento_esperado: 'Deveria ser em português' }
    )
  end

  it 'creates a Ticket scoped to the message and its conversation' do
    ticket = service.perform

    expect(ticket).to be_persisted
    expect(ticket.account_id).to eq(account.id)
    expect(ticket.user_id).to eq(user.id)
    expect(ticket.conversation_id).to eq(conversation.id)
    expect(ticket.context).to eq(message)
    expect(ticket.relatar_problema).to eq('IA respondeu errado')
    expect(ticket.comportamento_esperado).to eq('Deveria ser em português')
  end

  it 'starts as pending_sync so the CreateTaskJob owns the transition' do
    ticket = service.perform
    expect(ticket).to be_sync_pending_sync
  end

  it 'stores nil for blank comportamento_esperado instead of an empty string' do
    svc = described_class.new(
      user: user,
      message: message,
      params: { relatar_problema: 'algo', comportamento_esperado: '   ' }
    )
    expect(svc.perform.comportamento_esperado).to be_nil
  end

  it 'enqueues the ClickUp sync job with the fresh ticket id' do
    expect { service.perform }.to have_enqueued_job(Integrations::Clickup::CreateTaskJob)
  end
end
