require 'rails_helper'

# Upstream writes the SLA subjects inline in English; the fork translates them.
RSpec.describe AgentNotifications::ConversationNotificationsMailer, type: :mailer do
  let(:class_instance) { described_class.new }
  let!(:account) { create(:account, locale: 'pt_BR') }
  let(:agent) { create(:user, email: 'agent1@example.com', account: account) }
  let(:conversation) { create(:conversation, assignee: agent, account: account) }
  let(:sla_policy) { create(:sla_policy, account: account) }

  before do
    allow(described_class).to receive(:new).and_return(class_instance)
    allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(true)
  end

  {
    sla_missed_first_response: 'violou o SLA de primeira resposta',
    sla_missed_next_response: 'violou o SLA de próxima resposta',
    sla_missed_resolution: 'violou o SLA de tempo de resolução'
  }.each do |mail_name, expected|
    it "translates the #{mail_name} subject" do
      mail = described_class.with(account: account).public_send(mail_name, conversation, agent, sla_policy).deliver_now

      expect(mail.subject).to eq("Conversa [ID - #{conversation.display_id}] #{expected}")
      expect(mail.to).to eq([agent.email])
    end
  end
end
