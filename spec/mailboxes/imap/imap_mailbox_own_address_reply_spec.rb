require 'rails_helper'

# Somebody answering from the mailbox the inbox reads (the Gmail web UI of the same address)
# is the business replying, not the customer writing again. Stored as incoming, it put the
# human's words under the customer's name and had an AI agent on the inbox answer on top of
# the human, because for the agent the customer had just written.
RSpec.describe Imap::ImapMailbox do
  include ActionMailbox::TestHelper

  let(:channel) { create(:channel_email, :imap_email) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, email: 'customer@example.com', account: account) }
  let!(:conversation) do
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:reply_subject) { 'Re: pedido' }

  before do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming,
                     sender: contact, source_id: 'customer-1@example.com')
  end

  def deliver(**headers)
    mail = create_inbound_email_from_mail(to: 'customer@example.com', subject: reply_subject, body: 'Pode sim.', **headers).mail
    described_class.new.process(mail, channel)
  end

  it 'stores a threaded reply from the inbox address as outgoing, with no sender and its source id' do
    expect { deliver(from: channel.email, in_reply_to: 'customer-1@example.com', message_id: 'own-1@example.com') }
      .to change(conversation.messages, :count).by(1)

    reply = conversation.messages.find_by(source_id: 'own-1@example.com')
    expect(reply).to be_outgoing
    expect(reply.sender).to be_nil
    expect(reply.content_attributes.dig('email', 'from')).to eq([channel.email])
  end

  it 'reads the inbox address case-insensitively' do
    deliver(from: channel.email.upcase, in_reply_to: 'customer-1@example.com', message_id: 'own-2@example.com')

    expect(conversation.messages.find_by(source_id: 'own-2@example.com')).to be_outgoing
  end

  it 'threads by References when there is no In-Reply-To' do
    deliver(from: channel.email, references: '<customer-1@example.com>', message_id: 'own-3@example.com')

    expect(conversation.messages.find_by(source_id: 'own-3@example.com')).to be_outgoing
  end

  # The send path skips an outgoing message that already has a source id, which is the only
  # thing keeping the customer from getting the same reply twice.
  it 'does not send the reply again' do
    allow(ConversationReplyMailer).to receive(:with).and_call_original

    perform_enqueued_jobs(only: SendReplyJob) do
      deliver(from: channel.email, in_reply_to: 'customer-1@example.com', message_id: 'own-4@example.com')
    end

    expect(ConversationReplyMailer).not_to have_received(:with)
  end

  it 'opens nothing for mail from the inbox address that threads into no conversation' do
    expect do
      deliver(from: channel.email, in_reply_to: 'nowhere@example.com', message_id: 'own-5@example.com')
    end.to not_change(Conversation, :count).and(not_change(Contact, :count)).and(not_change(Message, :count))
  end

  it 'keeps a customer reply that copies the inbox as incoming from the customer' do
    deliver(from: 'customer@example.com', cc: channel.email, in_reply_to: 'customer-1@example.com', message_id: 'cust-2@example.com')

    reply = conversation.messages.find_by(source_id: 'cust-2@example.com')
    expect(reply).to be_incoming
    expect(reply.sender).to eq(contact)
  end
end
