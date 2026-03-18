FactoryBot.define do
  factory :recurring_scheduled_message do
    account
    inbox
    conversation
    association :author, factory: :user
    content { 'Recurring scheduled message content' }
    recurrence_rule do
      {
        frequency: 'weekly',
        interval: 1,
        week_days: [1],
        end_type: 'never'
      }
    end
    status { :active }
  end
end
