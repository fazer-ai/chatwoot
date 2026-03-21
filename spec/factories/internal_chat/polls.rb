# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_poll, class: 'InternalChat::Poll' do
    association :message, factory: [:internal_chat_message, :poll]
    question { 'What is your favorite color?' }
    multiple_choice { false }
    public_results { true }
    allow_revote { true }
    expires_at { nil }
  end
end
