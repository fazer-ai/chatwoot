# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_poll_vote, class: 'InternalChat::PollVote' do
    association :option, factory: :internal_chat_poll_option
    user
  end
end
