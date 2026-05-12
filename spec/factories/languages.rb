FactoryBot.define do
  factory :language do
    sequence(:code) { |n| "lc-#{n}" }
    sequence(:name) { |n| "Language #{n}" }
    sequence(:position) { |n| n }
  end
end
