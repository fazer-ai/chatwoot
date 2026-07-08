require 'rails_helper'

RSpec.describe Conversations::TranscriptPdfService do
  let(:conversation) { create(:conversation) }
  let(:service) { described_class.new(conversation: conversation) }

  describe '#perform' do
    let(:grover) { instance_double(Grover, to_pdf: 'PDFBYTES') }

    before do
      allow(Grover).to receive(:new).and_return(grover)
    end

    it 'returns the bytes from Grover' do
      expect(service.perform).to eq('PDFBYTES')
    end

    it 'releases the semaphore slot after a successful render' do
      before_available = described_class::SEMAPHORE.available_permits
      service.perform
      expect(described_class::SEMAPHORE.available_permits).to eq(before_available)
    end

    it 'releases the semaphore slot when the render raises' do
      allow(grover).to receive(:to_pdf).and_raise(StandardError, 'boom')
      before_available = described_class::SEMAPHORE.available_permits

      expect { service.perform }.to raise_error(StandardError, 'boom')
      expect(described_class::SEMAPHORE.available_permits).to eq(before_available)
    end

    # Concurrency contract: if every slot in the process semaphore is already
    # taken, a new caller waits up to ACQUIRE_TIMEOUT and then reports overload
    # instead of silently blocking a Puma thread forever.
    it 'raises OverloadError when the semaphore is fully saturated' do
      stub_const("#{described_class}::ACQUIRE_TIMEOUT", 0)
      # Drain every slot.
      described_class::SEMAPHORE.available_permits.times { described_class::SEMAPHORE.acquire }

      expect { service.perform }.to raise_error(described_class::OverloadError)
    ensure
      described_class::SEMAPHORE.release(described_class::MAX_CONCURRENT - described_class::SEMAPHORE.available_permits)
    end
  end

  describe '#filename' do
    it 'includes the conversation display id' do
      expect(service.filename).to eq("transcricao_#{conversation.display_id}.pdf")
    end
  end
end
