require 'rails_helper'

describe '/survey/response', type: :request do
  def install(values)
    values.each { |name, value| InstallationConfig.where(name: name).first_or_initialize.update!(value: value) }
    GlobalConfig.clear_cache
  end

  before do
    install(
      'BRAND_NAME' => 'Chatwoot',
      'BRAND_COLOR' => '#1F93FF',
      'WIDGET_BRAND_URL' => 'https://www.chatwoot.com',
      'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.svg'
    )
  end

  describe 'GET survey/responses/{uuid}' do
    it 'renders the page correctly when called' do
      conversation = create(:conversation)
      get survey_response_url(id: conversation.uuid)
      expect(response).to be_successful
    end

    it 'returns 404 when called with invalid conversation uuid' do
      get survey_response_url(id: '')
      expect(response).to have_http_status(:not_found)
    end

    # The customer only mistyped a link, or the conversation was deleted. The page renders and
    # the Vue app surfaces the error from the public endpoint; a Rails error page would not.
    it 'still renders for a uuid that matches no conversation' do
      get survey_response_url(id: SecureRandom.uuid)

      expect(response).to be_successful
      expect(response.body).to include 'Chatwoot'
    end

    it 'still renders for a uuid that is not even a uuid' do
      get survey_response_url(id: 'not-a-uuid')

      expect(response).to be_successful
    end

    context 'when the account configured a brand' do
      let(:account) { create(:account) }
      let(:conversation) { create(:conversation, account: account) }

      before do
        account.enable_features!('branded_email_templates')
        account.update!(
          brand_name: 'Guichê Live',
          brand_url: 'https://www.guichelive.com.br',
          brand_color: '#F82323'
        )
      end

      it 'dresses the page in the brand of that account' do
        get survey_response_url(id: conversation.uuid)

        expect(response.body).to include 'Guichê Live'
        expect(response.body).to include 'https://www.guichelive.com.br'
        expect(response.body).to include BrandColor.surface('#F82323')
      end

      it 'names the account in the tab, not the installation' do
        get survey_response_url(id: conversation.uuid)

        expect(response.body).to include '<title>Guichê Live</title>'
      end

      it 'keeps the installation brand for an account that configured none' do
        get survey_response_url(id: create(:conversation).uuid)

        expect(response.body).to include 'Chatwoot'
        expect(response.body).not_to include 'Guichê Live'
      end

      it 'tells the page to keep the branding footer by default' do
        get survey_response_url(id: conversation.uuid)

        expect(response.body).to include '"DISABLE_BRANDING":false'
      end

      it 'tells the page to drop the branding footer when the account may' do
        account.enable_features!('disable_branding')

        get survey_response_url(id: conversation.uuid)

        expect(response.body).to include '"DISABLE_BRANDING":true'
      end
    end
  end
end
