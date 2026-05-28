# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_channel, class: 'InternalChat::Channel' do
    account
    sequence(:name) { |n| "Channel #{n}" }
    channel_type { :public_channel }
    status { :active }

    trait :public_channel do
      channel_type { :public_channel }
    end

    trait :private_channel do
      channel_type { :private_channel }
    end

    trait :dm do
      channel_type { :dm }
      name { nil }
    end

    trait :archived do
      status { :archived }
    end

    trait :with_category do
      association :category, factory: :internal_chat_category
    end
  end
end
