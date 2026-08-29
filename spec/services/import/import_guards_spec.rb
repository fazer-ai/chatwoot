require 'rails_helper'

# The guards live in an initializer and are prepended at boot; what is worth covering is
# which level each one reads, because getting that wrong is silent in both directions.
describe 'ImportGuards' do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:contact_inbox) do
    ContactInboxWithContactBuilder.new(source_id: 'quem@example.com', inbox: inbox,
                                       contact_attributes: { name: 'Quem', email: 'quem@example.com' }).perform
  end

  def new_conversation
    Conversation.create!(account_id: account.id, inbox_id: inbox.id,
                         contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id)
  end

  context 'when the inbox has an active agent bot' do
    before do
      bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot, status: :active)
      inbox.reload
    end

    it 'starts a conversation pending outside an import, as it always has' do
      expect(new_conversation.status).to eq('pending')
    end

    # An archive thread is created resolved on purpose: born in that state it fires no
    # resolution event and lands in no report. The bot override would undo that for the
    # whole archive at once.
    it 'leaves the status alone while writing an archive' do
      conversation = Import::SilentWrite.wrap { new_conversation }
      expect(conversation.status).to eq('open')
      expect(conversation.assignee_agent_bot_id).to be_nil
    end

    # A gap thread is live work recovered a minute late, and has to be routed like any
    # other arrival or nobody works it until they reload.
    it 'routes a gap thread the way an arrival would be' do
      conversation = Import::SilentWrite.wrap(announce: true) { new_conversation }
      expect(conversation.status).to eq('pending')
      expect(conversation.assignee_agent_bot_id).to be_present
    end

    it 'still resolves a blocked contact at either level, which is not the import to undo' do
      contact_inbox.contact.update!(blocked: true)
      archived = Import::SilentWrite.wrap { new_conversation }
      announced = Import::SilentWrite.wrap(announce: true) { new_conversation }
      expect([archived.status, announced.status]).to eq(%w[resolved resolved])
    end
  end

  describe 'the jobs a new contact would start on its own' do
    it 'skips the Gravatar fetch for an archive, where one request per contact is a flood' do
      expect do
        Import::SilentWrite.wrap do
          create(:contact, account: account, email: "arquivo-#{SecureRandom.hex(4)}@example.com")
        end
      end.not_to have_enqueued_job(Avatar::AvatarFromGravatarJob)
    end

    it 'fetches it for a gap contact, where it is one request like any arrival' do
      expect do
        Import::SilentWrite.wrap(announce: true) do
          create(:contact, account: account, email: "gap-#{SecureRandom.hex(4)}@example.com")
        end
      end.to have_enqueued_job(Avatar::AvatarFromGravatarJob)
    end
  end

  describe 'the fan-out around a written message' do
    it 'reaches nothing at either level' do
      conversation = Import::SilentWrite.wrap { new_conversation }
      expect do
        Import::SilentWrite.wrap do
          create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: :incoming, content: 'historia')
        end
      end.not_to have_enqueued_job(EventDispatcherJob)
    end
  end
end
