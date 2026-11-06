require 'rails_helper'

# The Enterprise half of the guards. A Company is created as a side effect of importing a
# contact with a business address, and its own callback fetches a favicon off the domain --
# two models away from anything the OSS guards intercept, so neither the dispatcher guards
# nor the two on Contact ever see it.
describe 'ImportGuards' do
  let(:account) { create(:account) }

  it 'fetches a favicon for a company created outside an import, as it always has' do
    expect { create(:company, account: account, domain: 'empresa.example.com') }
      .to have_enqueued_job(Avatar::AvatarFromFaviconJob)
  end

  # One request per company at a third party that never agreed to it, over an archive that
  # is a decade of mail.
  it 'fetches none while writing an archive' do
    expect { Import::SilentWrite.wrap { create(:company, account: account, domain: 'empresa.example.com') } }
      .not_to have_enqueued_job(Avatar::AvatarFromFaviconJob)
  end

  it 'fetches one for a gap company, where it is one request like any arrival' do
    expect { Import::SilentWrite.wrap(announce: true) { create(:company, account: account, domain: 'empresa.example.com') } }
      .to have_enqueued_job(Avatar::AvatarFromFaviconJob)
  end

  # Transcription spends Captain credits per file. An archive of forwarded voice notes
  # drains the balance transcribing conversations closed before the feature existed.
  describe 'an audio attachment' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    def attach_audio
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      attachment = message.attachments.new(account_id: account.id, file_type: :audio)
      attachment.file.attach(io: StringIO.new('audio'), filename: 'nota.ogg', content_type: 'audio/ogg')
      message.save!
    end

    def audio(**level) = Import::SilentWrite.wrap(**level) { attach_audio }

    it 'is transcribed outside an import, as it always has been' do
      expect { attach_audio }.to have_enqueued_job(Messages::AudioTranscriptionJob)
    end

    it 'is not transcribed while writing an archive' do
      expect { audio }.not_to have_enqueued_job(Messages::AudioTranscriptionJob)
    end

    it 'is transcribed for a gap row, where it is one file like any arrival' do
      expect { audio(announce: true) }.to have_enqueued_job(Messages::AudioTranscriptionJob)
    end
  end
end
