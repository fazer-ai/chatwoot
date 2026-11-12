require 'rails_helper'

RSpec.describe 'MESSAGE_SEARCH_MIN_QUERY_LENGTH configuration', type: :request do
  let(:super_admin) { create(:super_admin) }

  it 'is offered on the general settings page' do
    sign_in(super_admin, scope: :super_admin)
    get '/super_admin/app_config'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('app_config[MESSAGE_SEARCH_MIN_QUERY_LENGTH]')
  end

  it 'is saved from the general settings page' do
    sign_in(super_admin, scope: :super_admin)
    post '/super_admin/app_config', params: { app_config: { MESSAGE_SEARCH_MIN_QUERY_LENGTH: '3' } }

    expect(response).to redirect_to(super_admin_app_config_path(config: 'general'))
    expect(GlobalConfig.get_value('MESSAGE_SEARCH_MIN_QUERY_LENGTH')).to eq('3')
  end

  it 'reaches the dashboard global config' do
    create(:installation_config, name: 'MESSAGE_SEARCH_MIN_QUERY_LENGTH', value: 3)
    get '/app/login'

    expect(response.body).to include('"MESSAGE_SEARCH_MIN_QUERY_LENGTH":3')
  end
end
