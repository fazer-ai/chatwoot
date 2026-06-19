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
  self.table_name = 'channel_instagram'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :access_token if Chatwoot.encryption_configured?

  AUTHORIZATION_ERROR_THRESHOLD = 1

  # Single source of truth for the Graph API version every Instagram call
  # in the app pins. Aligned with what the Meta App is configured for in
  # production (v24.0). Bumping is a one-line change here.
  #
  # Overridable at runtime via `InstallationConfig['INSTAGRAM_API_VERSION']`
  # for the two paths that already read it from there (MessageText,
  # MessageBuilder) — see `.api_version` below.
  GRAPH_API_VERSION = 'v24.0'.freeze

  def self.api_version
    GlobalConfigService.load('INSTAGRAM_API_VERSION', GRAPH_API_VERSION)
  end

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

  SUBSCRIBED_FIELDS = %w[messages message_reactions messaging_seen].freeze

  # Meta has been rejecting POST /subscribed_apps on graph.instagram.com
  # with the cryptic 'method type: post' error (same pattern as /me).
  # Try a sequence of request shapes — comma-separated string in body,
  # then comma-separated string in query, then graph.facebook.com. First
  # one that returns 2xx wins; logs detail what failed so an operator
  # can read the trail.
  def subscribe
    # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
    %i[subscribe_via_body subscribe_via_query subscribe_via_facebook_graph].each do |strategy|
      response = send(strategy)
      if response.success?
        Rails.logger.info("[instagram] subscribe ok for channel=#{id} via=#{strategy}")
        return true
      end
      log_subscribe_attempt(strategy, response)
    end

    Rails.logger.warn("[instagram] all subscribe strategies failed for channel=#{id}")
    false
  rescue StandardError => e
    Rails.logger.warn("[instagram] subscribe exception for channel=#{id}: #{e.class.name}: #{e.message}")
    false
  end

  def log_subscribe_attempt(strategy, response)
    Rails.logger.warn(
      "[instagram] subscribe #{strategy} failed for channel=#{id}: " \
      "status=#{response.code} body=#{response.body.to_s[0, 200]}"
    )
    true
  end

  # Comma-separated string in the request body — Meta's documented shape
  # for state-changing POSTs on subscribed_apps.
  def subscribe_via_body
    HTTParty.post(
      "https://graph.instagram.com/#{self.class.api_version}/#{instagram_id}/subscribed_apps",
      body: { subscribed_fields: SUBSCRIBED_FIELDS.join(','), access_token: access_token }
    )
  end

  # Original shape — comma-separated in the query string. Some Meta API
  # paths only accept this variant.
  def subscribe_via_query
    HTTParty.post(
      "https://graph.instagram.com/#{self.class.api_version}/#{instagram_id}/subscribed_apps",
      query: { subscribed_fields: SUBSCRIBED_FIELDS.join(','), access_token: access_token }
    )
  end

  # Last resort: Facebook Graph endpoint. IGAA tokens sometimes route
  # through `graph.facebook.com` for the cross-app subscription surface.
  def subscribe_via_facebook_graph
    HTTParty.post(
      "https://graph.facebook.com/#{self.class.api_version}/#{instagram_id}/subscribed_apps",
      body: { subscribed_fields: SUBSCRIBED_FIELDS.join(','), access_token: access_token }
    )
  end

  def unsubscribe
    response = HTTParty.delete(
      "https://graph.instagram.com/#{self.class.api_version}/#{instagram_id}/subscribed_apps",
      query: {
        access_token: access_token
      }
    )
    Rails.logger.warn("[instagram] unsubscribe failed for channel=#{id}: status=#{response.code} body=#{response.body}") unless response.success?
    true
  rescue StandardError => e
    Rails.logger.warn("[instagram] unsubscribe exception for channel=#{id}: #{e.class.name}: #{e.message}")
    true
  end

  def access_token
    Instagram::RefreshOauthTokenService.new(channel: self).access_token
  end

  # Public re-entry point. Useful in a Rails console when an existing
  # channel needs to be re-subscribed (e.g., the original subscribe was
  # silenced by Meta and an operator wants to retry without recreating
  # the inbox). Returns the same boolean as `subscribe`.
  def try_subscribe!
    subscribe
  end
end
