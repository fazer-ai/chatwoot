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

  # `hold_on_reply` means "if the customer writes back first, do not send this". A row that
  # is incoming, public and not a reaction is the whole trigger, and an imported row passes
  # that test the same way a live one does.
  describe 'a scheduled message waiting on the customer to reply' do
    let(:conversation) { new_conversation }
    let(:scheduled) do
      create(:scheduled_message, account: account, inbox: inbox, conversation: conversation,
                                 scheduled_at: 2.days.from_now, hold_on_reply: true, status: :pending)
    end

    def import(created_at, **level)
      Import::SilentWrite.wrap(**level) do
        create(:message, account: account, inbox: inbox, conversation: conversation,
                         message_type: :incoming, content: 'historia', created_at: created_at)
      end
    end

    it 'holds it when a live reply arrives, which is what the flag is for' do
      scheduled
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, content: 'oi')
      expect(scheduled.reload.status).to eq('held')
    end

    # The archive row is years old, so `scheduled_at > created_at` is true of every pending
    # scheduled message in the account: one imported ticket would hold the lot.
    it 'leaves it alone while writing an archive' do
      scheduled
      import(3.years.ago)
      expect(scheduled.reload.status).to eq('pending')
    end

    # A gap row is a reply that did arrive, just late. Holding is the right answer there.
    it 'holds it for a gap row, which is a real reply we learned about late' do
      scheduled
      import(1.minute.ago, announce: true)
      expect(scheduled.reload.status).to eq('held')
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
