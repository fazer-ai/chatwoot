# frozen_string_literal: true

FactoryBot.define do
  factory :disparo do
    account
    sequence(:name) { |n| "Disparo #{n}" }
    status { :draft }
    mode { :exclusive_cloud }
    template_name { 'welcome_back' }
  end

  factory :disparo_inbox do
    disparo
    inbox { association :inbox, account: disparo.account }
    provider { :cloud }
  end

  factory :disparo_target do
    disparo
    conversation
    contact { conversation.contact }
    inbox { conversation.inbox }
    state { :pending }
  end

  factory :disparo_event do
    disparo_target
    event_type { :queued }
  end

  factory :disparo_audience_snapshot do
    disparo
    filter_dsl { {} }
    inbox_ids { [] }
    total_eligible { 0 }
  end
end
