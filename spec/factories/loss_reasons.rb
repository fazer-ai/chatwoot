FactoryBot.define do
  factory :loss_reason do
    sequence(:name) { |n| "Reason #{n}" }
    sequence(:position) { |n| n }
    active { true }
  end
end
