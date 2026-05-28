# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_message, class: 'InternalChat::Message' do
    account
    association :channel, factory: :internal_chat_channel
    association :sender, factory: :user
    content { 'Hello, this is a test message' }
    content_type { :text }

    trait :with_parent do
      association :parent, factory: :internal_chat_message
    end

    trait :poll do
      content_type { :poll }
    end

    trait :system do
      content_type { :system }
    end
  end
end
