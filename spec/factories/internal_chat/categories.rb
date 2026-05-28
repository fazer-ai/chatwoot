# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_category, class: 'InternalChat::Category' do
    account
    sequence(:name) { |n| "Category #{n}" }
    position { 0 }
  end
end
