FactoryBot.define do
  factory :conversation_pin do
    conversation
    account

    before(:build) do |conversation_pin|
      conversation_pin.user ||= create(:user, account: conversation_pin.account)
    end
  end
end
