require 'rails_helper'

# Captain answers under its own sender type, so "not an agent bot" would have sealed its replies
# as a person's. The rule is the sender being a User, not the sender being a known kind of robot.
# This half lives under spec/enterprise because the community suite strips enterprise/ before it
# runs, and Captain::Assistant goes with it.
describe 'MetaHumanAgent' do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:captain) { create(:captain_assistant, account: account) }
  let(:bodies) { [] }

  def human_agent_feature(value)
    %w[ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT].each do |name|
      InstallationConfig.where(name: name).first_or_initialize.update!(value: value)
    end
    GlobalConfig.clear_cache
  end

  before { human_agent_feature(true) }

  describe Instagram::SendOnInstagramService do
    let!(:channel) { create(:channel_instagram, account: account) }
    let(:inbox) { channel.inbox }
    let!(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, contact: contact, inbox: inbox, contact_inbox: contact_inbox, account: account) }
    let(:message) do
      create(:message, message_type: :outgoing, conversation: conversation, inbox: inbox, account: account, sender: captain)
    end

    before do
      allow(HTTParty).to receive(:post) do |_url, **options|
        bodies << options[:body]
        instance_double(HTTParty::Response, :success? => true, :parsed_response => { 'message_id' => 'mid.sent' })
      end
    end

    it 'sends a Captain reply exactly as it sends with the feature off' do
      described_class.new(message: message).perform
      with_feature = bodies.last

      message.update!(source_id: nil)
      human_agent_feature(false)
      described_class.new(message: message).perform

      expect(message.sender_type).to eq('Captain::Assistant')
      expect(with_feature).to eq(bodies.last)
      expect(with_feature).not_to have_key(:tag)
      expect(with_feature).not_to have_key(:messaging_type)
    end
  end

  describe Facebook::SendOnFacebookService do
    # Declared before the channel: creating a page channel subscribes to Meta's webhooks, and a
    # `let!` registers its hook where it is written.
    before do
      allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
      allow(Facebook::Messenger::Bot).to receive(:deliver) do |params, **_options|
        bodies << params
        { message_id: 'mid.sent' }.to_json
      end
    end

    let!(:channel) { create(:channel_facebook_page, account: account) }
    let!(:inbox) { create(:inbox, channel: channel, account: account, greeting_enabled: false) }
    let!(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, contact: contact, inbox: inbox, contact_inbox: contact_inbox, account: account) }
    let(:message) do
      create(:message, message_type: :outgoing, conversation: conversation, inbox: inbox, account: account, sender: captain)
    end

    it 'sends a Captain reply as a plain response, never under the human agent seal' do
      described_class.new(message: message).perform

      expect(message.sender_type).to eq('Captain::Assistant')
      expect(bodies.last).to include(messaging_type: 'RESPONSE')
      expect(bodies.last).not_to have_key(:tag)
    end
  end
end
