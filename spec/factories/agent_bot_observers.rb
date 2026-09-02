FactoryBot.define do
  factory :agent_bot_observer do
    inbox
    agent_bot
    status { 'active' }
  end
end
