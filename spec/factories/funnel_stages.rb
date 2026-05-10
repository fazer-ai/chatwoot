FactoryBot.define do
  factory :funnel_stage do
    sequence(:name) { |n| "Stage #{n}" }
    sequence(:position) { |n| n }
    color { '#94a3b8' }
    active { true }
    closed { false }
    requires_loss_reason { false }
  end
end
