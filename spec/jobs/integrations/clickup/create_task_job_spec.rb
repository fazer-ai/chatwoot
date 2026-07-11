require 'rails_helper'

RSpec.describe Integrations::Clickup::CreateTaskJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, name: 'Fábio Rocha') }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:ticket) do
    create(:ticket, account: account, user: agent, context: message, conversation: conversation)
  end
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }
  let(:successful_response) do
    {
      'id' => 'CU_TASK_1',
      'url' => 'https://app.clickup.com/t/CU_TASK_1',
      'status' => { 'id' => 'sc_open', 'status' => 'aberto' }
    }
  end

  before do
    allow(Integrations::Clickup::Client).to receive(:new).and_return(client)
  end

  # Captures the kwargs the job passed to Client#create_task so per-field
  # assertions read off a plain hash instead of digging into RSpec mock internals.
  def stub_capture_create_task(response = successful_response)
    captured = {}
    allow(client).to receive(:create_task) do |**kwargs|
      captured.merge!(kwargs)
      response
    end
    captured
  end

  context 'when ClickUp returns a task' do
    before { allow(client).to receive(:create_task).and_return(successful_response) }

    it 'stamps the ClickUp coordinates on the ticket and flips to synced' do
      described_class.new.perform(ticket.id)

      ticket.reload
      expect(ticket).to be_sync_synced
      expect(ticket.clickup_task_id).to eq('CU_TASK_1')
      expect(ticket.clickup_task_url).to eq('https://app.clickup.com/t/CU_TASK_1')
      expect(ticket.clickup_status_id).to eq('sc_open')
      expect(ticket.clickup_status_name).to eq('aberto')
      expect(ticket.sync_error).to be_nil
    end

    # ClickUp task name is what shows up on the ops team's list view — the
    # ticket id lets them cross-reference back to Meus Tickets, and the
    # excerpt gives enough context to triage without opening the task.
    it 'names the ClickUp task "<id> - <problem excerpt>"' do
      captured = stub_capture_create_task
      ticket.update!(relatar_problema: 'A IA poderia ter respondido em outro idioma')

      described_class.new.perform(ticket.id)

      expect(captured[:name]).to eq("#{ticket.id} - A IA poderia ter respondido em outro idioma")
    end

    it 'caps the problem excerpt in the task name at 50 chars so the ClickUp list stays scannable' do
      captured = stub_capture_create_task
      long_body = 'Este é um relato bem longo com muito detalhe explicando o que aconteceu de errado e todos os contornos'
      ticket.update!(relatar_problema: long_body)

      described_class.new.perform(ticket.id)

      expect(captured[:name]).to start_with("#{ticket.id} - ")
      # Truncate uses ' ' as separator so it clips on the nearest word — the
      # tail is a Unicode ellipsis courtesy of ActiveSupport.
      body_part = captured[:name].delete_prefix("#{ticket.id} - ")
      expect(body_part.length).to be <= described_class::TASK_NAME_EXCERPT_LIMIT
    end

    it 'sends the Auris custom fields the ops team relies on to route the ticket' do
      captured = stub_capture_create_task

      described_class.new.perform(ticket.id)

      field_map = captured[:custom_fields].index_by { |f| f[:id] }
      expect(field_map[Integrations::Clickup::FieldMap::FIELDS[:relatar_problema]][:value])
        .to eq(ticket.relatar_problema)
      expect(field_map[Integrations::Clickup::FieldMap::FIELDS[:comportamento_esperado]][:value])
        .to eq(ticket.comportamento_esperado)
      expect(field_map[Integrations::Clickup::FieldMap::FIELDS[:user_id]][:value])
        .to eq(agent.id.to_s)
      expect(field_map[Integrations::Clickup::FieldMap::FIELDS[:user_name]][:value])
        .to eq('Fábio Rocha')
      expect(field_map[Integrations::Clickup::FieldMap::FIELDS[:account_id]][:value])
        .to eq(account.id)
      expect(field_map[Integrations::Clickup::FieldMap::FIELDS[:contexto]][:value])
        .to eq(Integrations::Clickup::FieldMap::CONTEXTO_OPTIONS[:mensagem])
    end

    it 'sends the aurischat deeplink pointing at the exact message so ops can jump straight in' do
      captured = stub_capture_create_task

      with_modified_env FRONTEND_URL: 'https://chat.auris.ia.br/' do
        described_class.new.perform(ticket.id)
      end

      url_field = captured[:custom_fields].find { |f| f[:id] == Integrations::Clickup::FieldMap::FIELDS[:aurischat_url] }
      expect(url_field[:value])
        .to eq("https://chat.auris.ia.br/app/accounts/#{account.id}/conversations/#{conversation.display_id}?messageId=#{message.id}")
    end
  end

  it 'chooses the Produção ambiente option when FRONTEND_URL is the auris prod host' do
    captured = stub_capture_create_task

    with_modified_env FRONTEND_URL: 'https://chat.auris.ia.br' do
      described_class.new.perform(ticket.id)
    end

    env_field = captured[:custom_fields].find { |f| f[:id] == Integrations::Clickup::FieldMap::FIELDS[:ambiente] }
    expect(env_field[:value]).to eq(Integrations::Clickup::FieldMap::AMBIENTE_OPTIONS[:producao])
  end

  it 'chooses the Homologação ambiente option on any non-prod URL' do
    captured = stub_capture_create_task

    with_modified_env FRONTEND_URL: 'https://chat-hmlg.auris.ia.br' do
      described_class.new.perform(ticket.id)
    end

    env_field = captured[:custom_fields].find { |f| f[:id] == Integrations::Clickup::FieldMap::FIELDS[:ambiente] }
    expect(env_field[:value]).to eq(Integrations::Clickup::FieldMap::AMBIENTE_OPTIONS[:homologacao])
  end

  context 'when the API key is not configured' do
    before { allow(client).to receive(:configured?).and_return(false) }

    it 'fails the ticket immediately without hitting the API — no retry' do
      described_class.new.perform(ticket.id)

      expect(client).not_to have_received(:create_task) if client.respond_to?(:create_task)
      ticket.reload
      expect(ticket).to be_sync_sync_failed
      expect(ticket.sync_error).to match(/CLICKUP_API_KEY/)
    end
  end

  context 'when ClickUp rejects the credentials' do
    before do
      allow(client).to receive(:create_task).and_raise(Integrations::Clickup::Client::Unauthorized, '401')
    end

    # Auth errors are terminal — retrying won't fix a bad token.
    it 'goes straight to sync_failed without scheduling a retry' do
      expect do
        described_class.new.perform(ticket.id)
      end.not_to have_enqueued_job(described_class)

      ticket.reload
      expect(ticket).to be_sync_sync_failed
      expect(ticket.sync_error).to eq('401')
    end
  end

  context 'when ClickUp is transiently unavailable' do
    before do
      allow(client).to receive(:create_task).and_raise(Integrations::Clickup::Client::ProviderUnavailable, 'timeout')
    end

    it 'increments the attempt counter and reschedules with backoff on the first failure' do
      expect do
        described_class.new.perform(ticket.id)
      end.to have_enqueued_job(described_class).with(ticket.id)

      ticket.reload
      expect(ticket.sync_attempts).to eq(1)
      expect(ticket).to be_sync_pending_sync
      expect(ticket.sync_error).to eq('timeout')
    end

    it 'gives up after MAX_ATTEMPTS so a permanently broken key does not cycle forever' do
      ticket.update!(sync_attempts: described_class::MAX_ATTEMPTS - 1)

      expect do
        described_class.new.perform(ticket.id)
      end.not_to have_enqueued_job(described_class)

      ticket.reload
      expect(ticket).to be_sync_sync_failed
      expect(ticket.sync_attempts).to eq(described_class::MAX_ATTEMPTS)
    end
  end

  it 'is a no-op when the ticket has already been synced (avoids double-fire on manual retry)' do
    ticket.update!(sync_status: :synced, clickup_task_id: 'existing')
    allow(client).to receive(:create_task)

    described_class.new.perform(ticket.id)

    expect(client).not_to have_received(:create_task)
  end

  it 'is a no-op when the ticket has been deleted' do
    ticket.destroy!
    expect { described_class.new.perform(ticket.id) }.not_to raise_error
  end
end
