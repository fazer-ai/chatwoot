require 'rails_helper'
describe ActionCableListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  # Typing payloads reach the contact, so they ship the contact-sized hash.
  # Building the expectation from the same allowlist the listener uses keeps
  # this honest: changing CONTACT_PUSH_KEYS updates both sides at once.
  let(:redacted_conversation_data) do
    conversation.push_event_data.slice(*Conversations::EventDataPresenter::CONTACT_PUSH_KEYS)
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Current.user = nil
    Current.account = nil
  end

  describe '#account_cache_invalidated' do
    let!(:event) do
      Events::Base.new(
        :'account.cache_invalidated',
        Time.zone.now,
        account: account,
        cache_keys: account.cache_keys
      )
    end

    it 'sends cache invalidation to account agents and admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
        'account.cache_invalidated',
        {
          cache_keys: account.cache_keys,
          account_id: account.id
        }
      )

      listener.account_cache_invalidated(event)
    end
  end

  describe '#message_created' do
    let(:event_name) { :'message.created' }
    let!(:message) do
      create(:message, message_type: 'outgoing',
                       account: account, inbox: inbox, conversation: conversation)
    end
    let!(:event) { Events::Base.new(event_name, Time.zone.now, message: message) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'message.created',
        message.push_event_data.merge(account_id: account.id)
      )
      listener.message_created(event)
    end

    it 'sends message to all hmac verified contact inboxes' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      conversation.contact_inbox.update!(hmac_verified: true)
      # creating a non verified contact inbox to ensure the events are not sent to it
      create(:contact_inbox, contact: conversation.contact, inbox: inbox)
      verified_contact_inbox = create(:contact_inbox, contact: conversation.contact, inbox: inbox, hmac_verified: true)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token, verified_contact_inbox.pubsub_token
        ),
        'message.created',
        message.push_event_data.merge(account_id: account.id)
      )
      listener.message_created(event)
    end
  end

  describe '#typing_on' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_on', { conversation: redacted_conversation_data,
                                    user: agent.push_event_data,
                                    account_id: account.id,
                                    is_private: false }
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_on with contact' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: conversation.contact, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, agent.pubsub_token
        ),
        'conversation.typing_on', { conversation: redacted_conversation_data,
                                    user: conversation.contact.push_event_data,
                                    account_id: account.id,
                                    is_private: false }
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_on with agent bot' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:agent_bot) { create(:agent_bot, account: account) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent_bot, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, agent.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_on', { conversation: redacted_conversation_data,
                                    user: agent_bot.push_event_data,
                                    account_id: account.id,
                                    is_private: false }
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_off' do
    let(:event_name) { :'conversation.typing_off' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_off', { conversation: redacted_conversation_data,
                                     user: agent.push_event_data,
                                     account_id: account.id,
                                     is_private: false }
      )
      listener.conversation_typing_off(event)
    end
  end

  describe '#contact_deleted' do
    let(:event_name) { :'contact.deleted' }
    let!(:contact) { create(:contact, account: account) }
    let(:contact_data) { contact.push_event_data.merge(account_id: contact.account_id) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, contact_data: contact_data) }

    it 'sends message to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        ["account_#{account.id}"],
        'contact.deleted',
        contact_data
      )
      listener.contact_deleted(event)
    end
  end

  describe '#conversation_pinned' do
    let(:pinned_at) { Time.zone.now.to_f }
    let(:pin_data) do
      {
        account_id: account.id,
        user_id: agent.id,
        conversation_id: conversation.display_id,
        pinned_at: pinned_at
      }
    end
    let!(:event) { Events::Base.new(:'conversation.pinned', Time.zone.now, conversation_pin: pin_data) }

    it 'sends the message only to the agent who pinned the conversation' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'conversation.pinned',
        {
          account_id: account.id,
          conversation_id: conversation.display_id,
          pinned_at: pinned_at
        }
      )

      listener.conversation_pinned(event)
    end

    it 'does not broadcast when the user is gone' do
      event = Events::Base.new(:'conversation.pinned', Time.zone.now, conversation_pin: pin_data.merge(user_id: 0))

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      listener.conversation_pinned(event)
    end
  end

  describe '#conversation_unpinned' do
    let(:pin_data) do
      {
        account_id: account.id,
        user_id: agent.id,
        conversation_id: conversation.display_id,
        pinned_at: Time.zone.now.to_f
      }
    end
    let!(:event) { Events::Base.new(:'conversation.unpinned', Time.zone.now, conversation_pin: pin_data) }

    it 'sends the message only to the agent who unpinned the conversation' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'conversation.unpinned',
        {
          account_id: account.id,
          conversation_id: conversation.display_id,
          pinned_at: pin_data[:pinned_at]
        }
      )

      listener.conversation_unpinned(event)
    end
  end

  describe '#notification_deleted' do
    let(:event_name) { :'notification.deleted' }
    let!(:notification) { create(:notification, account: account, user: agent) }
    let(:notification_data) do
      {
        id: notification.id,
        user_id: agent.id,
        account_id: account.id
      }
    end
    let!(:event) { Events::Base.new(event_name, Time.zone.now, notification_data: notification_data) }

    it 'sends message to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'notification.deleted',
        {
          account_id: notification.account_id,
          notification: {
            id: notification.id
          },
          unread_count: 1,
          count: 1
        }
      )

      listener.notification_deleted(event)
    end
  end

  describe '#notification_updated' do
    let(:event_name) { :'notification.updated' }
    let!(:notification) { create(:notification, account: account, user: agent) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, notification: notification) }

    it 'sends notification to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'notification.updated',
        {
          account_id: notification.account_id,
          notification: notification.push_event_data,
          unread_count: 1,
          count: 1
        }
      )

      listener.notification_updated(event)
    end
  end

  describe '#conversation_updated' do
    let(:event_name) { :'conversation.updated' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    before do
      conversation.add_labels(['support'])
      # Agents and the contact now get one broadcast each. Every example below
      # pins exactly one of the two, so the other still has to be allowed
      # through or it trips the constrained expectation.
      allow(ActionCableBroadcastJob).to receive(:perform_later)
    end

    it 'sends update to inbox members' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token, admin.pubsub_token],
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id)
      )
      listener.conversation_updated(event)
    end

    it 'sends the contact its own broadcast built from the allowlist' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [conversation.contact_inbox.pubsub_token],
        'conversation.updated',
        redacted_conversation_data.merge(account_id: account.id)
      )
      listener.conversation_updated(event)
    end

    it 'broadcast event with label data' do
      expect(conversation.reload.push_event_data[:labels]).to eq(conversation.labels.pluck(:name))

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token, admin.pubsub_token],
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id)
      )
      listener.conversation_updated(event)
    end

    it 'merges broadcast_metadata into the payload as event_metadata' do
      metadata = { source: 'reaction_toggle' }
      tagged_event = Events::Base.new(event_name, Time.zone.now, conversation: conversation, broadcast_metadata: metadata)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token, admin.pubsub_token],
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id, event_metadata: metadata)
      )
      listener.conversation_updated(tagged_event)
    end

    # The contact still needs the event (the widget refreshes its own state off
    # it), so the fix is a narrower payload, not a dropped broadcast.
    it 'still reaches the contact when metadata is present' do
      metadata = { source: 'reaction_toggle' }
      tagged_event = Events::Base.new(event_name, Time.zone.now, conversation: conversation, broadcast_metadata: metadata)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [conversation.contact_inbox.pubsub_token],
        'conversation.updated',
        redacted_conversation_data.merge(account_id: account.id, event_metadata: metadata)
      )
      listener.conversation_updated(tagged_event)
    end
  end

  # The bug this guards: `last_non_activity_message` filters `message_type` but
  # not `private`, so a trailing private note is exactly what it resolves to —
  # and these three events broadcast to `contact_inbox_tokens`. Assert on the
  # note's literal content so the example fails loudly if the payload is ever
  # re-unified, whatever key the content ends up under.
  #
  # The `agent context` example below is the general guard: the private note is
  # only the leak that was found first, and asserting on the allowlist catches
  # the next field someone adds to `push_data` without asserting on each by name.
  describe 'private note leakage to the contact' do
    let(:secret) { 'Internal only: customer has an overdue invoice' }
    let(:contact_token) { conversation.contact_inbox.pubsub_token }

    before do
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, content: secret)
    end

    it 'keeps the private note out of every contact-bound conversation payload' do
      payloads = []
      allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _event, payload|
        payloads << payload if tokens.include?(contact_token)
      end

      listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conversation))
      listener.conversation_status_changed(Events::Base.new(:'conversation.status_changed', Time.zone.now, conversation: conversation))
      listener.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))
      # All three typing events share `typing_conversation_data`, so all three
      # belong here — they are also the highest-frequency vector, firing per
      # keystroke rather than per status change.
      listener.conversation_typing_on(Events::Base.new(:'conversation.typing_on', Time.zone.now,
                                                       conversation: conversation, user: agent, is_private: true))
      listener.conversation_recording(Events::Base.new(:'conversation.recording', Time.zone.now,
                                                       conversation: conversation, user: agent, is_private: true))
      listener.conversation_typing_off(Events::Base.new(:'conversation.typing_off', Time.zone.now,
                                                        conversation: conversation, user: agent, is_private: true))

      expect(payloads.size).to eq(6)
      expect(payloads.to_s).not_to include(secret)
    end

    # The general guard, and the whole point of the allowlist. It asserts on the
    # SHAPE of the contact payload instead of on any one field, so the next key
    # added to `push_data` — CE, Enterprise or Pro — fails here rather than
    # shipping to the contact's browser. `last_non_activity_message` and Pro's
    # `kanban_task` both got in because the previous denylist only knew about
    # the fields someone had remembered to name.
    it 'never sends the contact a key outside the allowlist' do
      keys = []
      allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _event, payload|
        keys.concat(payload.keys) if tokens.include?(contact_token)
      end

      listener.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conversation))
      listener.conversation_status_changed(Events::Base.new(:'conversation.status_changed', Time.zone.now, conversation: conversation))
      listener.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))

      allowed = Conversations::EventDataPresenter::CONTACT_PUSH_KEYS +
                Conversations::EventDataPresenter::CONTACT_SAFE_EVENT_KEYS +
                %i[account_id]
      expect(keys.uniq - allowed).to be_empty
    end

    it 'keeps the operational fields agents work with out of the contact copy' do
      conversation.update!(custom_attributes: { internal_score: 'high risk' }, priority: 'urgent')
      conversation.add_labels(['inadimplente'])

      payload = nil
      allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _event, data|
        payload = data if tokens.include?(contact_token)
      end
      listener.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))

      expect(payload.keys).not_to include(:labels, :custom_attributes, :priority, :meta, :additional_attributes)
      expect(payload.to_s).not_to include('inadimplente', 'high risk')
    end

    it 'still gives the agents the private note as the chat list preview' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_including(agent.pubsub_token),
        'conversation.updated',
        hash_including(last_non_activity_message: hash_including(content: secret))
      )

      listener.conversation_updated(Events::Base.new(:'conversation.updated', Time.zone.now, conversation: conversation))
    end
  end

  shared_examples 'scheduled message event broadcast' do |method_name, event_name|
    it 'broadcasts to account admins and inbox members' do
      scheduled_message = create(:scheduled_message, account: account, inbox: inbox, conversation: conversation, author: agent)
      event = Events::Base.new(event_name, Time.zone.now, scheduled_message: scheduled_message)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
        event_name,
        scheduled_message.push_event_data.merge(account_id: account.id)
      )

      listener.public_send(method_name, event)
    end
  end

  describe '#scheduled_message_created' do
    it_behaves_like 'scheduled message event broadcast', :scheduled_message_created, 'scheduled_message.created'
  end

  describe '#scheduled_message_updated' do
    it_behaves_like 'scheduled message event broadcast', :scheduled_message_updated, 'scheduled_message.updated'
  end

  describe '#scheduled_message_deleted' do
    it_behaves_like 'scheduled message event broadcast', :scheduled_message_deleted, 'scheduled_message.deleted'
  end

  describe '#inbox_provider_connection_updated' do
    let(:event_name) { :'inbox.provider_connection_updated' }
    let(:provider_connection) do
      { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,qr', 'error' => nil }
    end
    let(:event) { Events::Base.new(event_name, Time.zone.now, inbox: inbox, provider_connection: provider_connection) }

    it 'sends only the connection status to non-admin agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'inbox.provider_connection_updated',
        { inbox_id: inbox.id, provider_connection: { connection: 'connecting' }, account_id: account.id }
      )
      allow(ActionCableBroadcastJob).to receive(:perform_later).with([admin.pubsub_token], anything, anything)

      listener.inbox_provider_connection_updated(event)
    end

    it 'sends the QR code and error only to administrators' do
      allow(ActionCableBroadcastJob).to receive(:perform_later).with([agent.pubsub_token], anything, anything)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [admin.pubsub_token],
        'inbox.provider_connection_updated',
        {
          inbox_id: inbox.id,
          provider_connection: { connection: 'connecting', qr_data_url: 'data:image/png;base64,qr', error: nil },
          account_id: account.id
        }
      )

      listener.inbox_provider_connection_updated(event)
    end

    context 'when a reach-out time-lock is present' do
      let(:provider_connection) do
        { 'connection' => 'connecting', 'reachout_time_lock' => { 'is_active' => true, 'time_enforcement_ends' => '2026-06-19T21:52:39.000Z' } }
      end

      it 'includes the lock in the agent broadcast (agents see the banner)' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          [agent.pubsub_token],
          'inbox.provider_connection_updated',
          {
            inbox_id: inbox.id,
            provider_connection: {
              connection: 'connecting',
              reachout_time_lock: { 'is_active' => true, 'time_enforcement_ends' => '2026-06-19T21:52:39.000Z' }
            },
            account_id: account.id
          }
        )
        allow(ActionCableBroadcastJob).to receive(:perform_later).with([admin.pubsub_token], anything, anything)

        listener.inbox_provider_connection_updated(event)
      end
    end

    context 'when a new-chat cap is present' do
      let(:provider_connection) do
        { 'connection' => 'open', 'new_chat_cap' => { 'capping_status' => 'CAPPED', 'total_quota' => 100, 'used_quota' => 100 } }
      end

      it 'includes the cap in the agent broadcast' do
        expect(ActionCableBroadcastJob).to receive(:perform_later).with(
          [agent.pubsub_token],
          'inbox.provider_connection_updated',
          {
            inbox_id: inbox.id,
            provider_connection: {
              connection: 'open',
              new_chat_cap: { 'capping_status' => 'CAPPED', 'total_quota' => 100, 'used_quota' => 100 }
            },
            account_id: account.id
          }
        )
        allow(ActionCableBroadcastJob).to receive(:perform_later).with([admin.pubsub_token], anything, anything)

        listener.inbox_provider_connection_updated(event)
      end
    end
  end

  describe '#conversation_unread_count_changed' do
    let(:event_name) { :'conversation.unread_count_changed' }
    let!(:agent_without_inbox_access) { create(:user, account: account, role: :agent) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

    before do
      account.enable_features!(:conversation_unread_counts)
    end

    it 'sends a lightweight refresh event to inbox agents and admins' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
        'conversation.unread_count_changed',
        {
          account_id: account.id
        }
      )

      listener.conversation_unread_count_changed(event)
    end

    it 'does not broadcast unread count refresh to agents outside the inbox' do
      expect(ActionCableBroadcastJob).not_to receive(:perform_later).with(
        array_including(agent_without_inbox_access.pubsub_token),
        anything,
        anything
      )

      listener.conversation_unread_count_changed(event)
    end

    it 'does not broadcast when conversation unread counts feature is disabled' do
      account.disable_features!(:conversation_unread_counts)

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      listener.conversation_unread_count_changed(event)
    end

    it 'supports deleted conversation data' do
      event = Events::Base.new(
        event_name,
        Time.zone.now,
        conversation_data: {
          id: conversation.id,
          account_id: account.id,
          inbox_id: conversation.inbox_id
        }
      )

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(agent.pubsub_token, admin.pubsub_token),
        'conversation.unread_count_changed',
        {
          account_id: account.id
        }
      )

      listener.conversation_unread_count_changed(event)
    end
  end
end
