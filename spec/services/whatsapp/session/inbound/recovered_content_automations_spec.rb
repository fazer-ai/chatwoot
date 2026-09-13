require 'rails_helper'

# A message the backend could not decrypt in time is stored as a placeholder with no content, and the
# message itself arrives later under the same id and is written over that row. `message_created` fired
# for the placeholder, so a rule filtered on the message content never saw the body that finally
# arrived (fazer-ai/chatwoot#491).
#
# Driven through the session dispatcher with the jobs drained, rather than by calling the listener,
# because what is under test is which rules run across the two arrivals: the evaluation happens in
# `EventDispatcherJob`, the order between the arrival's job and the recovery's is not guaranteed, and a
# listener called directly would agree with any of them.
RSpec.describe 'automations on the content that arrives after its own placeholder' do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

  let(:model) { Whatsapp::Session::Model }
  let(:sender) { model::Party.new(phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza') }
  let(:chat) { model::Address.phone('5541999990000') }
  let(:placeholder) { model::Content::Unsupported.new(reason: 'undecryptable') }
  let(:recovered) { model::Content::Text.new(body: 'Quero um orçamento') }
  let(:inbound) do
    model::InboundMessage.new(
      id: '3EB0RECOVER01', chat: chat, sender: sender, from_me: false,
      timestamp: 1_755_440_000_123, content: placeholder
    )
  end

  let!(:on_content) { rule('R_CONTEUDO', [condition('content', 'contains', ['orçamento'])]) }
  let!(:on_anything) { rule('R_QUALQUER', [condition('inbox_id', 'equal_to', [inbox.id])]) }
  let!(:on_other_content) { rule('R_OUTRO', [condition('content', 'contains', ['cancelar'])]) }

  before { allow(channel).to receive(:provider_service).and_return(backend) }

  def condition(key, operator, values)
    { 'attribute_key' => key, 'filter_operator' => operator, 'values' => values, 'query_operator' => nil }
  end

  def rule(name, conditions)
    create(:automation_rule, account: account, name: name, event_name: 'message_created',
                             conditions: conditions,
                             actions: [{ 'action_name' => 'send_message', 'action_params' => [name] }])
  end

  # The row every execution of a rule leaves behind: `ActionService#send_message` stamps the rule id on
  # the message it sends, so the count is the number of times that rule ran.
  #
  # `#>>'{}'` first, as `Message.hide_removed_reactions` does: `content_attributes` is a json column
  # written through `store coder: JSON`, so it holds a JSON string and a plain `->>` answers NULL for
  # every row, which counts every rule as never run.
  def ran(automation_rule)
    account.messages.where("((content_attributes#>>'{}')::jsonb)->>'automation_rule_id' = ?", automation_rule.id.to_s).count
  end

  def deliver(content)
    Whatsapp::Session::Inbound::Dispatcher.dispatch(
      channel, model::Event.build(model::Events::MessageReceived.new(message: inbound.with(content: content)))
    )
  end

  def arrive_and_settle(content)
    deliver(content)
    perform_enqueued_jobs
  end

  # The window has to outlast the recovery it is there to remember. WhatsApp re-encrypts when the
  # sender's phone comes back online, so hours are ordinary and a day is not unusual; a window measured
  # in minutes would be a rule running twice on the message it was supposed to protect.
  it 'remembers a rule execution for longer than a recovery takes' do
    expect(AutomationRuleListener::RULE_RUN_CLAIM_EXPIRY).to be >= 7.days
  end

  it 'runs a rule filtered on content when the content finally arrives' do
    arrive_and_settle(placeholder)
    expect(ran(on_content)).to eq(0)

    arrive_and_settle(recovered)

    expect(ran(on_content)).to eq(1)
    expect(inbox.conversations.last.labels).to be_empty.or include('orcamento')
  end

  it 'leaves a rule that does not filter on content at the one run the placeholder already gave it' do
    arrive_and_settle(placeholder)
    expect(ran(on_anything)).to eq(1)

    arrive_and_settle(recovered)

    expect(ran(on_anything)).to eq(1)
  end

  it 'evaluates the condition against the recovered body instead of firing every content rule' do
    arrive_and_settle(placeholder)
    arrive_and_settle(recovered)

    expect(ran(on_other_content)).to eq(0)
  end

  # Both evaluations run as jobs and nothing orders them, so the recovery can be the first thing that
  # ever evaluates this message. Whichever runs first must be the one that runs each rule.
  it 'runs each rule once when the recovery is evaluated before the arrival' do
    deliver(placeholder)
    deliver(recovered)

    perform_enqueued_jobs

    expect(ran(on_content)).to eq(1)
    expect(ran(on_anything)).to eq(1)
    expect(ran(on_other_content)).to eq(0)
  end

  it 'runs nothing again when the connector redelivers the recovery' do
    arrive_and_settle(placeholder)
    arrive_and_settle(recovered)

    arrive_and_settle(recovered)

    expect(ran(on_content)).to eq(1)
    expect(ran(on_anything)).to eq(1)
  end

  # The claim is per rule and per message, so the next message pays for none of it.
  it 'runs the same rule again for the next message that matches it' do
    arrive_and_settle(placeholder)
    arrive_and_settle(recovered)

    Whatsapp::Session::Inbound::Dispatcher.dispatch(
      channel, model::Event.build(model::Events::MessageReceived.new(message: inbound.with(id: '3EB0PLAIN01', content: recovered)))
    )
    perform_enqueued_jobs

    expect(ran(on_content)).to eq(2)
    expect(ran(on_anything)).to eq(2)
  end

  # Everything except the automations already ran the arrival. Re-firing `message_created` for the
  # recovery would reach all of them again: the webhook of an integration that counts messages, the
  # notification, the bot.
  it 'does not dispatch a second message_created for the same message' do
    dispatched = []
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, name, timestamp, data|
      dispatched << [name, data[:message].try(:source_id)]
      original.call(name, timestamp, data)
    end

    arrive_and_settle(placeholder)
    arrive_and_settle(recovered)

    expect(dispatched.count([Events::Types::MESSAGE_CREATED, '3EB0RECOVER01'])).to eq(1)
    expect(dispatched.count([Events::Types::MESSAGE_RECOVERED, '3EB0RECOVER01'])).to eq(1)
  end

  # A failure between the content write and the dispatch loses the automations for good: the redelivery
  # finds the row already written and comes back as a duplicate. So the dispatch goes before the chat
  # list refresh, which is the one of the two that a later event repairs on its own.
  it 'dispatches the recovery even when refreshing the chat list fails' do
    arrive_and_settle(placeholder)
    allow(Whatsapp::Session::Inbound::ChatList).to receive(:refresh).and_raise('the chat list is away')

    expect { deliver(recovered) }.to raise_error('the chat list is away')
    perform_enqueued_jobs

    expect(ran(on_content)).to eq(1)
  end

  # The history import writes its rows with every callback suppressed, so nothing ran when they landed.
  # The content of an archived message is not a message arriving, and rules answering traffic from weeks
  # ago is the one thing the import is careful never to do.
  it 'runs nothing for a placeholder the history import wrote' do
    contact = create(:contact, account: account, phone_number: '+5541999990000')
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5541999990000')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    Import::SilentWrite.wrap do
      Whatsapp::Session::Inbound::MessageWriter.new(
        conversation: conversation, inbound: inbound, sender: contact, imported: true
      ).perform
    end
    perform_enqueued_jobs

    arrive_and_settle(recovered)

    expect(inbox.messages.find_by(source_id: '3EB0RECOVER01').content).to eq('Quero um orçamento')
    expect(ran(on_content)).to eq(0)
    expect(ran(on_anything)).to eq(0)
  end

  # The claim is there to stop a second run, not to spend a rule's only chance on an attempt that never
  # acted: a rule whose execution raised (the database gone while a delayed rule is being scheduled) has
  # to be free again for the retry, which is what happens today.
  it 'frees a rule whose execution raised, so the retry still runs it' do
    attempts = 0
    build_action_service = AutomationRules::ActionService.method(:new)
    allow(AutomationRules::ActionService).to receive(:new) do |*args|
      attempts += 1
      raise 'the database went away' if attempts == 1

      build_action_service.call(*args)
    end

    deliver(placeholder)
    expect { perform_enqueued_jobs }.to raise_error('the database went away')

    # What Sidekiq does with the event whose job raised, which nothing else here stands in for.
    Rails.configuration.dispatcher.dispatch(
      Events::Types::MESSAGE_CREATED, Time.zone.now, message: inbox.messages.find_by(source_id: '3EB0RECOVER01')
    )
    perform_enqueued_jobs

    expect(ran(on_anything)).to eq(1)
  end

  # A placeholder that is never recovered is not held back: the arrival is what the agent sees, and a
  # content rule has nothing to match.
  it 'keeps the placeholder arrival immediate' do
    arrive_and_settle(placeholder)

    expect(ran(on_anything)).to eq(1)
    expect(ran(on_content)).to eq(0)
    expect(inbox.messages.find_by(source_id: '3EB0RECOVER01').content_attributes['unsupported_reason']).to eq('undecryptable')
  end
end
