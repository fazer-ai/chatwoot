require 'rails_helper'

describe Whatsapp::TemplateProcessorService do
  subject(:processed_parameters) { described_class.new(channel: channel, template_params: template_params).call.last }

  let(:sample_url) { 'https://scontent.whatsapp.net/v/t61.29466-34/sample_n.jpg?ccb=1-7&oh=01_Q5Aa&oe=6AA7FF50' }
  let(:template) do
    {
      'name' => 'promo',
      'status' => 'APPROVED',
      'language' => 'pt_BR',
      'category' => 'MARKETING',
      'components' => [
        { 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => [sample_url] } },
        { 'text' => 'Olá {{1}}', 'type' => 'BODY' }
      ]
    }
  end
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', message_templates: [template], validate_provider_config: false, sync_templates: false)
  end
  let(:template_params) do
    {
      'name' => 'promo',
      'language' => 'pt_BR',
      'processed_params' => {
        'body' => { '1' => 'Ana' },
        'header' => { 'media_url' => media_url, 'media_type' => 'image' }
      }
    }
  end

  context "when the agent sends the template's own sample media" do
    let(:media_url) { sample_url }

    # That URL is hosted on Meta's CDN, which answers 403 to Meta's own media fetcher, so it can only
    # be delivered as an uploaded media id.
    it 'uploads it and addresses it by id' do
      allow(Whatsapp::TemplateSampleMediaService).to receive(:new)
        .with(channel: channel, url: sample_url)
        .and_return(instance_double(Whatsapp::TemplateSampleMediaService, media_id: 'uploaded_id'))

      expect(processed_parameters).to include(
        { type: 'header', parameters: [{ type: 'image', image: { id: 'uploaded_id' } }] }
      )
    end
  end

  # A scheduled message or a campaign stores the sample URL at compose time. By the time it fires, the
  # sync has refreshed the template and Meta has re-signed the handle, so the stored string no longer
  # matches character for character.
  context 'when the stored sample URL carries a signature that has since rotated' do
    let(:media_url) { 'https://scontent.whatsapp.net/v/t61.29466-34/sample_n.jpg?ccb=1-7&oh=00_OldSig&oe=6A000000' }

    it 'uploads the handle the template carries now' do
      allow(Whatsapp::TemplateSampleMediaService).to receive(:new)
        .with(channel: channel, url: sample_url)
        .and_return(instance_double(Whatsapp::TemplateSampleMediaService, media_id: 'uploaded_id'))

      expect(processed_parameters).to include(
        { type: 'header', parameters: [{ type: 'image', image: { id: 'uploaded_id' } }] }
      )
    end
  end

  context 'when the agent supplies their own URL' do
    let(:media_url) { 'https://cdn.example.com/promo.jpg' }

    it 'sends it as a link' do
      expect(Whatsapp::TemplateSampleMediaService).not_to receive(:new)

      expect(processed_parameters).to include(
        { type: 'header', parameters: [{ type: 'image', image: { link: media_url } }] }
      )
    end
  end

  context 'when the provider is not whatsapp_cloud' do
    let(:media_url) { sample_url }
    let(:channel) { create(:channel_whatsapp, message_templates: [template], validate_provider_config: false, sync_templates: false) }

    it 'sends the sample media as a link, since only the Cloud API exposes a media store' do
      expect(Whatsapp::TemplateSampleMediaService).not_to receive(:new)

      expect(processed_parameters).to include(
        { type: 'header', parameters: [{ type: 'image', image: { link: sample_url } }] }
      )
    end
  end
end
