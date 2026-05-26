FactoryBot.define do
  factory :account_health_score do
    account
    score { 80 }
    captured_on { Date.current }
    breakdown do
      {
        'weighted_score' => 80,
        'kill_clause' => nil,
        'phase' => 'mature',
        'account_age_days' => 120,
        'metrics' => {},
        'groups' => {
          'outcomes' => { 'weight_total' => 40, 'sub_score_normalized' => 80, 'missing' => false },
          'operational' => { 'weight_total' => 25, 'sub_score_normalized' => 100, 'missing' => false },
          'engagement' => { 'weight_total' => 35, 'sub_score_normalized' => 70, 'missing' => false }
        }
      }
    end
  end
end
