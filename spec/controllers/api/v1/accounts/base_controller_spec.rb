require 'rails_helper'

RSpec.describe Api::V1::Accounts::BaseController do
  describe 'callback ordering' do
    # Re-declaring `before_action :current_account` in a subclass makes Rails
    # de-duplicate the callback and move it to the end of the chain, so
    # `validate_token_api_access` runs while `Current.account` is still nil and
    # every request authenticated with the `api_access_token` header fails
    # with a 500.
    it 'runs current_account before validate_token_api_access in every descendant' do
      Rails.application.eager_load!

      ([described_class] + described_class.descendants).each do |controller|
        filters = controller._process_action_callbacks.select { |callback| callback.kind == :before }.map(&:filter)
        validate_index = filters.index(:validate_token_api_access)
        next if validate_index.nil?

        expect(filters.index(:current_account)).to be < validate_index,
                                                   "#{controller.name} runs validate_token_api_access before current_account"
      end
    end
  end

  describe 'authentication context with Current.user' do
    controller(Api::V1::Accounts::BaseController) do
      def index
        render json: { success: true, account_id: Current.account.id, user_id: Current.account_user.user_id }
      end
    end

    let(:account) { create(:account) }
    let(:user) { create(:user) }

    before do
      create(:account_user, account: account, user: user)
    end

    it 'authorizes requests when identity is established via Current.user' do
      Current.user = user
      get :index, params: { account_id: account.id }
      expect(response).to have_http_status(:success)
      data = JSON.parse(response.body)
      expect(data['user_id']).to eq(user.id)
    ensure
      Current.reset
    end

    it 'returns unauthorized when Current.user is not a member of the account' do
      other_user = create(:user)
      Current.user = other_user
      get :index, params: { account_id: account.id }
      expect(response).to have_http_status(:unauthorized)
    ensure
      Current.reset
    end
  end
end
