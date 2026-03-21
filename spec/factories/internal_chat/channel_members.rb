# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_channel_member, class: 'InternalChat::ChannelMember' do
    association :channel, factory: :internal_chat_channel
    user
    role { :member }
    muted { false }
    favorited { false }

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
