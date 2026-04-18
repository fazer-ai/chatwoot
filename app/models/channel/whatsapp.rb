# rubocop:disable Layout/LineLength
# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  provider_connection            :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number      (phone_number) UNIQUE
#  index_channel_whatsapp_provider_connection  (provider_connection) WHERE ((provider)::text = ANY (ARRAY[('baileys'::character varying)::text, ('zapi'::character varying)::text])) USING gin
#
# rubocop:enable Layout/LineLength

class Channel::Whatsapp < ApplicationRecord # rubocop:disable Metrics/ClassLength
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud baileys zapi].freeze
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  has_one :inbox, as: :channel, dependent: :destroy

  after_create :sync_templates
  before_destroy :teardown_webhooks
  before_destroy :disconnect_channel_provider, if: -> { provider_service.respond_to?(:disconnect_channel_provider) }
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  def name
    'Whatsapp'
  end

  def provider_service
    case provider
    when 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    when 'baileys'
      Whatsapp::Providers::WhatsappBaileysService.new(whatsapp_channel: self)
    when 'zapi'
      Whatsapp::Providers::WhatsappZapiService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def use_internal_host?
    provider == 'baileys' && ENV.fetch('BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL', false)
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def update_provider_connection!(provider_connection)
    assign_attributes(provider_connection: provider_connection)
    # NOTE: Skip `validate_provider_config?` check
    save!(validate: false)
  end

  def provider_connection_data
    data = { connection: provider_connection['connection'] }
    if Current.account_user&.administrator?
      data[:qr_data_url] = provider_connection['qr_data_url']
      data[:error] = provider_connection['error']
    end
    data
  end

  def toggle_typing_status(typing_status, conversation:)
    return unless provider_service.respond_to?(:toggle_typing_status)

    recipient_id = conversation.contact.identifier || conversation.contact.phone_number
    last_message = conversation.messages.last
    provider_service.toggle_typing_status(typing_status, last_message: last_message, recipient_id: recipient_id)
  end

  def update_presence(status)
    return unless provider_service.respond_to?(:update_presence)

    provider_service.update_presence(status)
  end

  def read_messages(messages, conversation:)
    return unless provider_service.respond_to?(:read_messages)
    # NOTE: This is the default behavior, so `mark_as_read` being `nil` is the same as `true`.
    return if provider_config&.dig('mark_as_read') == false

    recipient_id = if provider == 'zapi'
                     conversation.contact.phone_number
                   else
                     conversation.contact.identifier || conversation.contact.phone_number
                   end

    provider_service.read_messages(messages, recipient_id: recipient_id)
  end

  def unread_conversation(conversation)
    return unless provider_service.respond_to?(:unread_message)

    # NOTE: For the Baileys provider, the last message is required even if it is an outgoing message.
    last_message = conversation.messages.last
    provider_service.unread_message(conversation.contact.phone_number, last_message) if last_message
  end

  def disconnect_channel_provider
    provider_service.disconnect_channel_provider
  rescue StandardError => e
    # NOTE: Don't prevent destruction if disconnect fails
    Rails.logger.error "Failed to disconnect channel provider: #{e.message}"
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
  def convert_provider!(new_provider:, new_provider_config:)
    # Serialize concurrent conversions of the same inbox. Without the lock,
    # two admin requests could both pass pre-validation, race the disconnect
    # and save, and leave webhooks/templates mismatched with the persisted
    # provider. `with_lock` issues SELECT FOR UPDATE and wraps the block in
    # a transaction; the loser waits until the winner commits.
    with_lock do
      previous_provider = provider
      previous_provider_config = provider_config.deep_dup
      normalized_new_config = new_provider_config || {}

      if new_provider == previous_provider
        errors.add(:provider, 'must be different from the current provider')
        raise ActiveRecord::RecordInvalid, self
      end

      # Pre-validate the new config without persisting, so we never terminate
      # the current provider session for a known-bad target config.
      assign_attributes(provider: new_provider, provider_config: normalized_new_config)
      unless valid?
        assign_attributes(provider: previous_provider, provider_config: previous_provider_config)
        raise ActiveRecord::RecordInvalid, self
      end
      # Snapshot provider_config AFTER valid? so we keep any fields populated
      # by before_validation callbacks (e.g. ensure_webhook_verify_token). The
      # final persist uses save!(validate: false), so we must not rely on a
      # second validation pass to replay those callbacks.
      validated_new_config = provider_config.deep_dup

      # Validation passed. Restore the old state briefly so the disconnect
      # call talks to the correct (old) endpoint, then reapply and persist
      # the new state. We call the service directly so a failed disconnect
      # propagates and aborts the conversion instead of silently leaving the
      # old session alive while the inbox points at the new provider.
      assign_attributes(provider: previous_provider, provider_config: previous_provider_config)
      # When converting away from whatsapp_cloud, mirror the destroy-time
      # cleanup so the Meta webhook subscription is torn down (embedded_signup
      # source); manual-setup channels follow the same no-op behavior as on
      # destruction. A teardown failure on a best-effort cleanup should not
      # abort the swap.
      if previous_provider == 'whatsapp_cloud'
        begin
          teardown_webhooks
        rescue StandardError => e
          Rails.logger.error "[WHATSAPP] Pre-conversion webhook teardown failed: #{e.message}"
        ensure
          # Reset the destroy-time guard so a later destroy! or subsequent
          # conversion on the same instance doesn't skip webhook removal.
          @webhook_teardown_initiated = false
        end
      end
      provider_service.disconnect_channel_provider if provider_service.respond_to?(:disconnect_channel_provider)

      assign_attributes(
        provider: new_provider,
        provider_config: validated_new_config,
        provider_connection: {},
        message_templates: {},
        message_templates_last_updated: nil
      )
      # Skip revalidation: the pre-flight valid? above is authoritative. A
      # second validate_provider_config? call here would re-hit the external
      # API and a transient failure could roll back the transaction after we
      # already disconnected the old session.
      save!(validate: false)

      setup_webhooks if should_auto_setup_webhooks?

      begin
        sync_templates
      rescue StandardError => e
        # Some provider sync_templates implementations stamp
        # `message_templates_last_updated` before the remote fetch. If the
        # fetch blows up, reset both columns so the inbox doesn't look
        # synced with zero templates and the scheduler will retry.
        update_columns(message_templates: {}, message_templates_last_updated: nil) # rubocop:disable Rails/SkipsModelValidations
        Rails.logger.error "[WHATSAPP] Post-conversion template sync failed: #{e.message}"
      end
    end

    self
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength

  def received_messages(messages, conversation)
    return unless provider_service.respond_to?(:received_messages)

    recipient_id = conversation.contact.identifier || conversation.contact.phone_number
    provider_service.received_messages(recipient_id, messages)
  end

  def on_whatsapp(phone_number)
    return unless provider_service.respond_to?(:on_whatsapp)

    provider_service.on_whatsapp(phone_number)
  end

  def delete_message(message, conversation:)
    return unless provider_service.respond_to?(:delete_message)

    recipient_id = if provider == 'zapi'
                     conversation.contact.phone_number.presence || conversation.contact.identifier
                   else
                     conversation.contact.identifier || conversation.contact.phone_number
                   end
    return if recipient_id.blank?

    provider_service.delete_message(recipient_id, message)
  end

  def edit_message(message, new_content, conversation:)
    return unless provider_service.respond_to?(:edit_message)

    recipient_id = conversation.contact.identifier || conversation.contact.phone_number
    provider_service.edit_message(recipient_id, message, new_content)
  end

  def sync_group(conversation, soft: false)
    return unless provider_service.respond_to?(:sync_group)

    provider_service.sync_group(conversation, soft: soft)
  end

  def allow_group_creation?
    provider_service.respond_to?(:allow_group_creation?) && provider_service.allow_group_creation?
  end

  delegate :setup_channel_provider, to: :provider_service
  delegate :presence_subscribe, to: :provider_service
  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service
  delegate :create_group, to: :provider_service
  delegate :update_group_subject, to: :provider_service
  delegate :update_group_description, to: :provider_service
  delegate :update_group_picture, to: :provider_service
  delegate :update_group_participants, to: :provider_service
  delegate :group_invite_code, to: :provider_service
  delegate :revoke_group_invite, to: :provider_service
  delegate :group_join_requests, to: :provider_service
  delegate :handle_group_join_requests, to: :provider_service
  delegate :group_leave, to: :provider_service
  delegate :group_setting_update, to: :provider_service
  delegate :group_join_approval_mode, to: :provider_service
  delegate :group_member_add_mode, to: :provider_service

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider.in?(%w[whatsapp_cloud baileys])
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    # NOTE: Guard against double execution during destruction due to the
    # `has_one :inbox, dependent: :destroy` relationship which will trigger this callback circularly
    return if @webhook_teardown_initiated

    @webhook_teardown_initiated = true
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end
end
