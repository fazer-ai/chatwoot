# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::MessageAttachment do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:message).class_name('InternalChat::Message') }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:file_type).with_values(image: 0, audio: 1, video: 2, file: 3) }
  end

  describe 'ActiveStorage attachment' do
    it 'has one attached file' do
      expect(described_class.new.file).to be_an_instance_of(ActiveStorage::Attached::One)
    end
  end

  describe 'factory' do
    it 'creates a valid attachment' do
      attachment = create(:internal_chat_message_attachment)
      expect(attachment).to be_valid
      expect(attachment).to be_persisted
    end

    it 'supports different file types' do
      image_attachment = build(:internal_chat_message_attachment, file_type: :image)
      expect(image_attachment).to be_image

      audio_attachment = build(:internal_chat_message_attachment, file_type: :audio)
      expect(audio_attachment).to be_audio

      video_attachment = build(:internal_chat_message_attachment, file_type: :video)
      expect(video_attachment).to be_video

      file_attachment = build(:internal_chat_message_attachment, file_type: :file)
      expect(file_attachment).to be_file
    end
  end
end
