require 'rails_helper'

# The Enterprise half of the guards. A Company is created as a side effect of importing a
# contact with a business address, and its own callback fetches a favicon off the domain --
# two models away from anything the OSS guards intercept, so neither the dispatcher guards
# nor the two on Contact ever see it.
describe 'ImportGuards' do
  let(:account) { create(:account) }

  it 'fetches a favicon for a company created outside an import, as it always has' do
    expect { create(:company, account: account, domain: 'empresa.example.com') }
      .to have_enqueued_job(Avatar::AvatarFromFaviconJob)
  end

  # One request per company at a third party that never agreed to it, over an archive that
  # is a decade of mail.
  it 'fetches none while writing an archive' do
    expect { Import::SilentWrite.wrap { create(:company, account: account, domain: 'empresa.example.com') } }
      .not_to have_enqueued_job(Avatar::AvatarFromFaviconJob)
  end

  it 'fetches one for a gap company, where it is one request like any arrival' do
    expect { Import::SilentWrite.wrap(announce: true) { create(:company, account: account, domain: 'empresa.example.com') } }
      .to have_enqueued_job(Avatar::AvatarFromFaviconJob)
  end
end
