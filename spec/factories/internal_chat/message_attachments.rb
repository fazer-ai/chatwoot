# frozen_string_literal: true

FactoryBot.define do
  factory :internal_chat_message_attachment, class: 'InternalChat::MessageAttachment' do
    association :message, factory: :internal_chat_message
    account { message.account }
    file_type { :image }
    file { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

    trait :audio do
      file_type { :audio }
    end

    trait :video do
      file_type { :video }
    end

    trait :file_type_file do
      file_type { :file }
    end
  end
end
