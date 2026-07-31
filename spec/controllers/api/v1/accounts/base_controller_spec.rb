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
end
