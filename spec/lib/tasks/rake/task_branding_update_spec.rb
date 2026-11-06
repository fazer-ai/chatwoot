require 'rake'
require 'rails_helper'

# The environment seeds the brand and the super admin edits it: a run of the task at container
# start must not undo what an operator saved on the Branding page.
RSpec.describe Rake::Task do
  subject(:task) { described_class['branding:update'] }

  before do
    described_class.clear
    Chatwoot::Application.load_tasks
    ConfigLoader.new.process
    allow($stdout).to receive(:puts)
  end

  def value_of(name)
    InstallationConfig.find_by!(name: name).value
  end

  it 'writes a key from the environment while it still holds its default' do
    with_modified_env BRAND_NAME: 'Acme', DISPLAY_MANIFEST: 'false' do
      task.invoke
    end

    expect(value_of('BRAND_NAME')).to eq('Acme')
    expect(value_of('DISPLAY_MANIFEST')).to be(false)
    expect(value_of('INSTALLATION_NAME')).to eq('Chatwoot')
  end

  it 'keeps a key that was changed from its default, whatever the environment says' do
    InstallationConfig.find_by!(name: 'BRAND_NAME').update!(value: 'Saved in the super admin')
    InstallationConfig.find_by!(name: 'LOGO').update!(value: 'https://acme.test/logo.svg')

    with_modified_env BRAND_NAME: 'From the environment' do
      task.invoke
    end

    expect(value_of('BRAND_NAME')).to eq('Saved in the super admin')
    # Unset in the environment used to mean "back to the default"; an edit is kept here too.
    expect(value_of('LOGO')).to eq('https://acme.test/logo.svg')
  end

  it 'writes every key from the environment again with BRANDING_FORCE' do
    InstallationConfig.find_by!(name: 'BRAND_NAME').update!(value: 'Saved in the super admin')

    with_modified_env BRAND_NAME: 'From the environment', BRANDING_FORCE: 'true' do
      task.invoke
    end

    expect(value_of('BRAND_NAME')).to eq('From the environment')
  end
end
