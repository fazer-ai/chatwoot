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

  def subscribe
    # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
    response = HTTParty.post(
      "https://graph.instagram.com/#{self.class.api_version}/#{instagram_id}/subscribed_apps",
      query: {
        subscribed_fields: %w[messages message_reactions messaging_seen],
        access_token: access_token
      }
    )
    # Webhook subscription is silent in the old code (rescue + true). If
    # Meta rejects with the same 'method type' / version-mismatch error
    # we've been chasing, the inbox would silently lose all incoming
    # messages. Surface failures as warnings so an operator can see them.
    Rails.logger.warn("[instagram] subscribe failed for channel=#{id}: status=#{response.code} body=#{response.body}") unless response.success?
    response.success?
  rescue StandardError => e
    Rails.logger.warn("[instagram] subscribe exception for channel=#{id}: #{e.class.name}: #{e.message}")
    false
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
end
