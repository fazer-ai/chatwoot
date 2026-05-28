# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_draft, class: 'InternalChat::Draft' do
    account
    user
    association :channel, factory: :internal_chat_channel
    content { 'Draft message content' }
  end
end
