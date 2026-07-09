FactoryBot.define do
  factory :ticket do
    relatar_problema { 'A resposta da IA veio em espanhol.' }
    comportamento_esperado { 'Deveria ter respondido em português.' }
    sync_status { :pending_sync }

    after(:build) do |ticket|
      ticket.account ||= create(:account)
      ticket.user ||= create(:user, account: ticket.account)
      ticket.conversation ||= create(:conversation, account: ticket.account)
      ticket.context ||= create(:message, account: ticket.account, conversation: ticket.conversation)
    end
  end
end
