# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_poll_option, class: 'InternalChat::PollOption' do
    association :poll, factory: :internal_chat_poll
    sequence(:text) { |n| "Option #{n}" }
    sequence(:position) { |n| n }
  end
end
