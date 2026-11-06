require 'rails_helper'

RSpec.describe Voice::CallTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account, phone_number: '+15551238888') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content_type: :voice_call) }
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, status: 'completed', message: message)
  end

  before do
    allow(Llm::SpeechToTextService).to receive(:available_for?).and_return(true)
    call.recording.attach(
      io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
      filename: 'call-recording.mp3',
      content_type: 'audio/mpeg'
    )
  end

  # Upstream stubs `reindex` on a message whose class only has it when OPENSEARCH_URL is set,
  # so its example dies on NoMethodError in any environment without search. Superseded by this
  # copy (fazer_ai_ee/spec/support/superseded_upstream_examples.rb).
  describe '#perform' do
    it 'reindexes before broadcasting so a retry after a reindex failure does not resend the update event' do
      call.update!(transcript: 'Existing transcript')
      allow(ChatwootApp).to receive(:advanced_search_allowed?).and_return(true)
      # `Message` mixes searchkick in at class-load time, and only when
      # `advanced_search_allowed?` -- which needs OPENSEARCH_URL, absent in test. So the
      # method the service calls does not exist on the class here and a verified double
      # refuses to stub it. Defining it completes the "search is on" simulation the stub
      # above starts, instead of the service dying on NoMethodError before the point.
      message.define_singleton_method(:reindex) { |*| nil }
      allow(message).to receive(:reindex).and_raise(StandardError, 'reindex boom')

      expect(message).not_to receive(:send_update_event)
      expect { described_class.new(call: call).perform }.to raise_error(StandardError, 'reindex boom')
    end
  end
end
