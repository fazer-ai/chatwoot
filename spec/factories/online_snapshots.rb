FactoryBot.define do
  factory :online_snapshot do
    account
    user
    snapshot_at { Time.current }
  end
end
