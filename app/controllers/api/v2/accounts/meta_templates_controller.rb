# Read-only view of the Meta WhatsApp templates cached on each Cloud
# WhatsApp channel. Fatia 2 of the Templates Meta story — lists what
# `Whatsapp::Providers::WhatsappCloudService#sync_templates` last pulled
# from Meta, and lets the operator trigger an on-demand refresh.
#
# The heavier CRUD (create / edit / delete / status webhook) lands in
# Fatias 3-4 on top of this same controller shell.
class Api::V2::Accounts::MetaTemplatesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_inbox
  before_action :ensure_cloud_provider

  def index
    templates = @inbox.channel.message_templates || []
    render json: {
      inbox: inbox_payload(@inbox),
      templates: templates,
      last_synced_at: @inbox.channel.message_templates_last_updated
    }
  end

  # On-demand refresh. Runs inline instead of enqueueing the job so the
  # operator gets the fresh data in the same request — Meta's list call is
  # a single roundtrip (with paging) and takes a couple of seconds.
  # Wrapped in `Whatsapp::Providers::TransientError` awareness could come
  # later; for a manual sync the error message is fine to surface as-is.
  def sync
    @inbox.channel.sync_templates
    templates = @inbox.channel.reload.message_templates || []
    render json: {
      inbox: inbox_payload(@inbox),
      templates: templates,
      last_synced_at: @inbox.channel.message_templates_last_updated
    }
  rescue StandardError => e
    Rails.logger.warn("[MetaTemplates#sync] inbox=#{@inbox.id} failed: #{e.class}: #{e.message}")
    render json: { error: I18n.t('errors.meta_templates.sync_failed') }, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize :meta_template, "#{action_name}?".to_sym
  end

  # Restricts operations to inboxes the current account actually owns; a
  # crafted `inbox_id` from another account gets a 404 instead of leaking
  # the template catalog cross-tenant.
  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  # This controller is Cloud-only. Baileys, Twilio-WhatsApp and the
  # other providers do not have Meta-approved templates in the same
  # sense, so a request against them returns 422 instead of an empty
  # payload the frontend might misread as "no templates".
  def ensure_cloud_provider
    return if @inbox.whatsapp? && @inbox.channel.try(:provider) == 'whatsapp_cloud'

    render json: { error: I18n.t('errors.meta_templates.non_cloud_inbox') }, status: :unprocessable_entity
  end

  def inbox_payload(inbox)
    channel = inbox.channel
    {
      id: inbox.id,
      name: inbox.name,
      phone_number: channel.try(:phone_number)
    }
  end
end
