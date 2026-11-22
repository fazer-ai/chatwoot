require 'rails_helper'

RSpec.describe Api::V1::Accounts::BaseController do
  describe 'callback ordering' do
    # Re-declaring `before_action :current_account` in a subclass makes Rails
    # de-duplicate the callback and move it to the end of the chain, so
    # `validate_token_api_access` runs while `Current.account` is still nil and
    # every request authenticated with the `api_access_token` header fails
    # with a 500.
    #
    # Enterprise controllers that break the order upstream, which the fork does not patch. Each one
    # must still break it: once upstream fixes it, the example fails and the entry goes.
    known_upstream_defects = {
      'Api::V1::Accounts::Captain::FaqSuggestionsController' => 'fazer-ai/chatwoot#1005'
    }

    it 'runs current_account before validate_token_api_access in every descendant' do
      Rails.application.eager_load!
      defects_seen = []

      ([described_class] + described_class.descendants).each do |controller|
        filters = controller._process_action_callbacks.select { |callback| callback.kind == :before }.map(&:filter)
        validate_index = filters.index(:validate_token_api_access)
        next if validate_index.nil?

        if known_upstream_defects.key?(controller.name)
          defects_seen << controller.name
          expect(filters.index(:current_account)).to be > validate_index,
                                                     "#{controller.name} is fixed upstream: drop it (#{known_upstream_defects[controller.name]})"
          next
        end

        expect(filters.index(:current_account)).to be < validate_index,
                                                   "#{controller.name} runs validate_token_api_access before current_account"
      end

      # An entry whose controller is gone, or no longer runs the check, is stale too.
      expect(defects_seen).to match_array(known_upstream_defects.keys) if ChatwootApp.enterprise?
    end
  end

  # Regressão: `validate_token_api_access` chamava `Current.account` direto.
  # Com a conta suspensa `Current.account` é nil, e a chamada estourava
  # `NoMethodError` — 500 para quem chamou, quando o correto é 401.
  #
  # Este patch vivia apenas como camada sobre a imagem local, nunca no git.
  describe 'validate_token_api_access com conta suspensa' do
    controller(Api::V1::Accounts::BaseController) do
      def index
        render json: { ok: true }
      end
    end

    it 'responde 401 quando Current.account é nil' do
      # Sem conta no contexto: é o estado de uma conta suspensa/inacessível.
      Current.reset if Current.respond_to?(:reset)
      Current.account = nil

      get :index

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('Account is suspended or inaccessible')
    end

    it 'não estoura NoMethodError (500) quando Current.account é nil' do
      Current.reset if Current.respond_to?(:reset)
      Current.account = nil

      expect { get :index }.not_to raise_error
      expect(response).not_to have_http_status(:internal_server_error)
    end

    it 'mantém o 403 quando a conta existe mas a API está desabilitada' do
      account = create(:account, api_and_webhooks_enabled: false)
      Current.account = account

      get :index

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include('API access is not enabled for this account')
    end
  end
end
