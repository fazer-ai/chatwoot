# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::NotificationService do
  let(:account) { create(:account) }
  let(:sender) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }
  let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: sender, content: 'Hello everyone') }

  before do
    dispatcher = double
    allow(dispatcher).to receive(:dispatch)
    allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
    allow(ActionCableBroadcastJob).to receive(:perform_later)
  end

  describe '#perform' do
    it 'broadcasts message notifications for channel members except the sender' do
      member1 = create(:user, account: account, role: :agent)
      member2 = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)
      create(:internal_chat_channel_member, channel: channel, user: member1)
      create(:internal_chat_channel_member, channel: channel, user: member2)

      described_class.new(message: message).perform

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        [member1.pubsub_token], 'notification.created', hash_including(notification_type: :internal_chat_message)
      )
      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        [member2.pubsub_token], 'notification.created', hash_including(notification_type: :internal_chat_message)
      )
      expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with(
        [sender.pubsub_token], 'notification.created', anything
      )
    end

    it 'does not broadcast message notifications for muted members' do
      muted_member = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)
      create(:internal_chat_channel_member, :muted, channel: channel, user: muted_member)

      described_class.new(message: message).perform

      expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with(
        [muted_member.pubsub_token], 'notification.created', anything
      )
    end

    it 'broadcasts mention notifications for mentioned users' do
      mentioned_user = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)
      create(:internal_chat_channel_member, channel: channel, user: mentioned_user)

      mention_message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://user/#{mentioned_user.id}/#{mentioned_user.name}) check this"
      )

      described_class.new(message: mention_message).perform

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        [mentioned_user.pubsub_token], 'notification.created', hash_including(notification_type: :internal_chat_mention)
      )
    end

    it 'broadcasts mention notifications for @all when sender is admin' do
      admin_sender = create(:user, account: account, role: :administrator)
      member1 = create(:user, account: account, role: :agent)
      member2 = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: admin_sender)
      create(:internal_chat_channel_member, channel: channel, user: member1)
      create(:internal_chat_channel_member, channel: channel, user: member2)

      all_message = create(
        :internal_chat_message, account: account, channel: channel, sender: admin_sender,
                                content: '@all please review'
      )

      described_class.new(message: all_message).perform

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        [member1.pubsub_token], 'notification.created', hash_including(notification_type: :internal_chat_mention)
      )
      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        [member2.pubsub_token], 'notification.created', hash_including(notification_type: :internal_chat_mention)
      )
      expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with(
        [admin_sender.pubsub_token], 'notification.created', anything
      )
    end

    it 'treats mentioned muted members as mentioned (mention overrides mute)' do
      muted_member = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)
      create(:internal_chat_channel_member, :muted, channel: channel, user: muted_member)

      mention_message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://user/#{muted_member.id}/#{muted_member.name}) check this"
      )

      described_class.new(message: mention_message).perform

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        [muted_member.pubsub_token], 'notification.created', hash_including(notification_type: :internal_chat_mention)
      )
    end

    it 'does not create Notification database records' do
      member = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)
      create(:internal_chat_channel_member, channel: channel, user: member)

      expect { described_class.new(message: message).perform }.not_to change(Notification, :count)
    end
  end
end
