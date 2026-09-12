# == Schema Information
#
# Table name: channel_instagram
#
#  id           :bigint           not null, primary key
#  access_token :string           not null
#  expires_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer          not null
#  instagram_id :string           not null
#
# Indexes
#
#  index_channel_instagram_on_instagram_id  (instagram_id) UNIQUE
#
class Channel::Instagram < ApplicationRecord
  include Channelable
  include Reauthorizable
  include Instagram::RequestOptions
  self.table_name = 'channel_instagram'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :access_token if Chatwoot.encryption_configured?

  AUTHORIZATION_ERROR_THRESHOLD = 1

  validates :access_token, presence: true
  validates :instagram_id, uniqueness: true, presence: true

  after_create_commit :subscribe
  before_destroy :unsubscribe

  def name
    'Instagram'
  end

  def create_contact_inbox(instagram_id, name)
    @contact_inbox = ::ContactInboxWithContactBuilder.new({
                                                            source_id: instagram_id,
                                                            inbox: inbox,
                                                            contact_attributes: { name: name, identifier: instagram_id }
                                                          }).perform
  end

  def subscribe
    # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
    response = HTTParty.post(
      "#{base_uri}/#{instagram_id}/subscribed_apps",
      query: {
        subscribed_fields: %w[messages message_reactions messaging_seen],
        access_token: access_token
      },
      **INSTAGRAM_SHORT_REQUEST_OPTIONS
    )
    return true if response.success?

    subscription_failed("Instagram answered #{response.code}")
  rescue StandardError => e
    subscription_failed("the request did not complete: #{e.class}")
  end

  # An inbox that did not subscribe exists and receives nothing, and it used to say so
  # nowhere: the answer was never read, every failure answered `true`, and the only trace
  # was a `debug` line. The operator saw a working inbox and no messages.
  #
  # There is no third state worth reporting here. Instagram refusing and Instagram not
  # answering leave the same inbox in the same condition, and they have the same remedy,
  # which is the one the reauthorization banner already asks for: reconnect, which runs
  # this again. `authorization_error!` rather than `prompt_reauthorization!` so the
  # channel's own threshold decides, which for this channel is one.
  def subscription_failed(reason)
    Rails.logger.error("[INSTAGRAM] inbox #{inbox&.id} did not subscribe to webhooks, so it will receive nothing: #{reason}")
    authorization_error!
    false
  end

  # Failing to unsubscribe must not stop the channel from being removed: the operator
  # asked for it to go, and Instagram's copy of the subscription is not ours to hold it
  # hostage. But it cannot be silent either, because we go on receiving webhooks for an
  # inbox that no longer exists, and the only way anyone finds out is by reading logs.
  def unsubscribe
    response = HTTParty.delete(
      "#{base_uri}/#{instagram_id}/subscribed_apps",
      query: {
        access_token: access_token
      },
      **INSTAGRAM_SHORT_REQUEST_OPTIONS
    )
    return true if response.success?

    log_unsubscribe_failure("Instagram answered #{response.code}")
  rescue StandardError => e
    log_unsubscribe_failure("the request did not complete: #{e.class}")
  end

  def log_unsubscribe_failure(reason)
    Rails.logger.error(
      "[INSTAGRAM] account #{account_id} removed instagram id #{instagram_id} and it is still subscribed there: #{reason}"
    )
    true
  end

  def access_token
    Instagram::RefreshOauthTokenService.new(channel: self).access_token
  end

  private

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
