require 'rails_helper'

RSpec.describe Attachment do
  let(:conversation) { create(:conversation) }

  it 'transcribes a voice note recorded on a private message' do
    message = create(:message, message_type: :outgoing, private: true,
                               conversation: conversation, account: conversation.account)

    expect do
      message.attachments.create!(
        account_id: message.account_id,
        file_type: :audio,
        file: fixture_file_upload('public/audio/widget/ding.mp3')
      )
    end.to have_enqueued_job(Messages::AudioTranscriptionJob)
  end
end
