# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_reaction, class: 'InternalChat::Reaction' do
    association :message, factory: :internal_chat_message
    user
    emoji { '👍' }
  end
end
