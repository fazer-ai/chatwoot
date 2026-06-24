FactoryBot.define do
  factory :ai_assignment_attempt do
    conversation
    account { conversation&.account || association(:account) }
    team { association(:team, account: account) }
    agent_assigned { nil }
    triggered_by { association(:user) }
    online_user_ids { [] }
  end
end
