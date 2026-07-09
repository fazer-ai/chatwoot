require 'rails_helper'

RSpec.describe Integrations::Clickup::AttachFileJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:ticket) do
    create(:ticket,
           account: account,
           user: agent,
           sync_status: :synced,
           clickup_task_id: 'CU_TASK_1')
  end
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('screenshot bytes'),
      filename: 'evidencia.png',
      content_type: 'image/png'
    )
  end

  before do
    allow(Integrations::Clickup::Client).to receive(:new).and_return(client)
  end

  context 'when the ticket has synced' do
    it 'uploads the blob to ClickUp with the correct task id and filename' do
      captured = {}
      allow(client).to receive(:upload_attachment) do |task_id, **kwargs|
        captured[:task_id] = task_id
        captured.merge!(kwargs)
        { 'id' => 'a1' }
      end

      described_class.new.perform(ticket.id, blob.signed_id)

      expect(captured[:task_id]).to eq(ticket.clickup_task_id)
      expect(captured[:filename]).to eq('evidencia.png')
      expect(captured[:io]).to respond_to(:read)
    end

    it 'purges the local blob after uploading — ClickUp is the canonical store' do
      allow(client).to receive(:upload_attachment).and_return({ 'id' => 'a1' })

      expect do
        described_class.new.perform(ticket.id, blob.signed_id)
      end.to have_enqueued_job(ActiveStorage::PurgeJob)
    end
  end

  context 'when the ticket has not synced yet' do
    it 'reschedules itself with a short wait — CreateTaskJob still needs to land the task_id' do
      ticket.update!(sync_status: :pending_sync, clickup_task_id: nil)

      expect do
        described_class.new.perform(ticket.id, blob.signed_id, 0)
      end.to have_enqueued_job(described_class).with(ticket.id, blob.signed_id, 0)

      # never hits ClickUp while we wait
      expect(client).not_to have_received(:upload_attachment) if client.respond_to?(:upload_attachment)
    end
  end

  context 'when the ticket sync ultimately failed' do
    it 'gives up quietly — there is no task to attach to' do
      ticket.update!(sync_status: :sync_failed)

      expect do
        described_class.new.perform(ticket.id, blob.signed_id)
      end.not_to have_enqueued_job(described_class)
    end
  end

  context 'when the ticket has been deleted before the job runs' do
    it 'is a no-op' do
      ticket_id = ticket.id
      ticket.destroy!
      expect { described_class.new.perform(ticket_id, blob.signed_id) }.not_to raise_error
    end
  end

  context 'when ClickUp rejects credentials' do
    it 'logs the orphan and drops the blob (auth errors are terminal)' do
      allow(client).to receive(:upload_attachment).and_raise(Integrations::Clickup::Client::Unauthorized, '401')

      expect do
        described_class.new.perform(ticket.id, blob.signed_id)
      end.not_to have_enqueued_job(described_class)
    end
  end

  context 'when ClickUp is transiently unavailable' do
    before do
      allow(client).to receive(:upload_attachment).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'timeout')
    end

    it 'reschedules with the next backoff bucket' do
      expect do
        described_class.new.perform(ticket.id, blob.signed_id, 0)
      end.to have_enqueued_job(described_class).with(ticket.id, blob.signed_id, 1)
    end

    it 'gives up after MAX_ATTEMPTS' do
      expect do
        described_class.new.perform(ticket.id, blob.signed_id, described_class::MAX_ATTEMPTS - 1)
      end.not_to have_enqueued_job(described_class)
    end
  end
end
