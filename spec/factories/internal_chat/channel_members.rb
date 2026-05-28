# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_channel_member, class: 'InternalChat::ChannelMember' do
    association :channel, factory: :internal_chat_channel
    user
    role { :member }
    muted { false }
    favorited { false }

    # AccountUser#add_to_public_internal_chat_channels auto-adds users to existing
    # public channels on account_user creation, so tests that explicitly create a
    # membership for an already-auto-joined (channel, user) pair would hit the
    # unique index. Reuse the existing record when present.
    initialize_with do
      channel_id = channel&.id
      user_id = user&.id
      if channel_id && user_id
        InternalChat::ChannelMember.find_or_initialize_by(
          internal_chat_channel_id: channel_id,
          user_id: user_id
        )
      else
        InternalChat::ChannelMember.new
      end
    end

    trait :admin do
      role { :admin }
    end

    trait :muted do
      muted { true }
    end

    trait :favorited do
      favorited { true }
    end
  end
end
