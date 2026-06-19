FactoryBot.define do
  factory :channel_instagram, class: 'Channel::Instagram' do
    account
    access_token { SecureRandom.hex(32) }
    instagram_id { SecureRandom.hex(16) }
    expires_at { 60.days.from_now }
    updated_at { 25.hours.ago }

    before :create do |channel|
      version = Channel::Instagram.api_version
      # Match the first subscribe strategy (body, comma-separated string)
      # without pinning to exact body — covers any subscribe variant.
      WebMock::API.stub_request(:post, "https://graph.instagram.com/#{version}/#{channel.instagram_id}/subscribed_apps")
                  .to_return(status: 200, body: '', headers: {})
      WebMock::API.stub_request(:delete, "https://graph.instagram.com/#{version}/#{channel.instagram_id}/subscribed_apps")
                  .to_return(status: 200, body: '', headers: {})
    end

    after(:create) do |channel|
      create(:inbox, channel: channel, account: channel.account)
    end
  end
end
