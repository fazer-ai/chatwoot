require 'rails_helper'

RSpec.describe Whatsapp::CampaignTemplateLiquidRenderer do
  let(:account)  { create(:account) }
  let(:user)     { create(:user, account: account, name: 'Maria Silva', email: 'maria@auris.test') }
  let(:contact)  { create(:contact, account: account, name: 'João Souza', phone_number: '+5511988887777', email: 'joao@example.test') }
  let(:inbox)    { create(:inbox, account: account) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, sender: user, audience: []) }

  def render(template_params)
    described_class.new(campaign: campaign, contact: contact, template_params: template_params).call
  end

  it 'returns the input untouched when there are no liquid tokens' do
    params = { 'name' => 'tpl', 'processed_params' => { 'body' => { '1' => 'olá pessoa' } } }
    expect(render(params)).to eq(params)
  end

  it 'renders contact tokens in body variables per contact' do
    params = { 'processed_params' => { 'body' => { '1' => 'Olá {{contact.first_name}}!' } } }
    rendered = render(params)
    expect(rendered['processed_params']['body']['1']).to eq('Olá João!')
  end

  it 'renders contact phone token via the alias drop' do
    params = { 'processed_params' => { 'body' => { '1' => 'Tel: {{contact.phone}}' } } }
    expect(render(params)['processed_params']['body']['1']).to eq('Tel: +5511988887777')
  end

  it 'renders agent email which the upstream UserDrop did not expose before' do
    params = { 'processed_params' => { 'body' => { '1' => 'Atendente: {{agent.email}}' } } }
    expect(render(params)['processed_params']['body']['1']).to eq('Atendente: maria@auris.test')
  end

  it 'renders header and button parameters too' do
    params = {
      'processed_params' => {
        'header' => { 'media_url' => 'https://cdn.test/{{contact.id}}.png' },
        'body' => { '1' => 'oi {{contact.name}}' },
        'buttons' => [{ 'type' => 'url', 'parameter' => 'cupom-{{contact.id}}' }]
      }
    }
    rendered = render(params)
    expect(rendered['processed_params']['header']['media_url']).to eq("https://cdn.test/#{contact.id}.png")
    expect(rendered['processed_params']['body']['1']).to eq('oi João Souza')
    expect(rendered['processed_params']['buttons'].first['parameter']).to eq("cupom-#{contact.id}")
  end

  it 'falls back to the original token when liquid syntax is invalid' do
    params = { 'processed_params' => { 'body' => { '1' => 'broken {{ contact.first_name' } } }
    expect(render(params)['processed_params']['body']['1']).to eq('broken {{ contact.first_name')
  end

  it 'does not mutate the input hash' do
    params = { 'processed_params' => { 'body' => { '1' => '{{contact.first_name}}' } } }
    original = params.deep_dup
    render(params)
    expect(params).to eq(original)
  end
end
