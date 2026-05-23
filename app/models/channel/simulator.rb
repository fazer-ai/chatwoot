# Channel type backing the WhatsApp simulator inbox auto-created on every
# account that lives in `environment = test`. The model is intentionally
# minimal — no per-channel configuration, no provider integration — because
# the simulator's job is to be a *fake* customer-side surface that talks to
# the real Chatwoot pipeline through the same public widget API
# (`Api::V1::Widget::*`) that `Channel::WebWidget` uses. Having a distinct
# `channel_type` is what lets the n8n webhook listener branch cleanly:
# memory keys in the simulator path use `conversation.id` instead of
# `contact.identifier` so test sessions don't collide with each other.
# == Schema Information
#
# Table name: channel_simulator
#
#  id            :bigint           not null, primary key
#  pubsub_token  :string
#  website_token :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer          not null
#
# Indexes
#
#  index_channel_simulator_on_account_id     (account_id)
#  index_channel_simulator_on_pubsub_token   (pubsub_token) UNIQUE
#  index_channel_simulator_on_website_token  (website_token) UNIQUE
#
class Channel::Simulator < ApplicationRecord
  include Channelable

  self.table_name = 'channel_simulator'

  has_secure_token :website_token
  has_secure_token :pubsub_token

  def name
    'Simulator'
  end

  # The widget API controllers and the configs jbuilder expect their
  # `@web_widget` to respond to a fixed set of accessors. The surface
  # below is the minimum needed so `Api::V1::Widget::*` treats a
  # simulator inbox interchangeably with a `Channel::WebWidget` — the
  # whole point of the simulator (a logged-in dashboard user
  # role-playing as a customer through the public widget API).
  # Always tag the contact as "Simulador" instead of letting Chatwoot mint
  # a Haikunator name. The simulator's role-play uses a stable customer
  # identity so the dashboard side reads a recognizable contact row.
  SIMULATOR_CONTACT_NAME = 'Simulador'.freeze

  def create_contact_inbox(additional_attributes = {})
    ::ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        name: SIMULATOR_CONTACT_NAME,
        additional_attributes: additional_attributes
      }
    ).perform
  end

  # Authorises the widget `toggle_status` endpoint so the simulator's
  # "Iniciar uma nova conversa" flow can resolve the current
  # conversation on the AurisChat side before the iframe reloads. The
  # public widget exposes a "Close" affordance off this flag too, but
  # we control the SDK UI here -- `end_conversation` is intentionally
  # absent from `selected_feature_flags`, so no SDK-side button shows.
  def end_conversation?
    true
  end

  def hmac_mandatory
    false
  end

  def hmac_token
    nil
  end

  # Feature flags the widget SDK reads at boot to toggle the attachment
  # button and the emoji picker in the chat footer. We turn both on by
  # default for the simulator so role-playing matches WhatsApp's
  # behaviour (image / document send + reaction-style emoji picking).
  def selected_feature_flags
    %w[attachments emoji_picker]
  end

  def pre_chat_form_enabled
    false
  end

  def pre_chat_form_options
    {}
  end

  def reply_time
    'in_a_few_minutes'
  end

  def welcome_tagline
    ''
  end

  def welcome_title
    ''
  end

  # Matches the WhatsApp brand green so the simulator UI feels native.
  def widget_color
    '#25D366'
  end

  # Mirror the WhatsApp channel's reactions support so the dashboard's
  # reaction toolbar lights up for messages in the Simulador inbox and
  # so `Api::V1::Accounts::Conversations::Messages::ReactionsController`
  # accepts the toggle. The simulator-side widget endpoint at
  # `Api::V1::Widget::ReactionsController` also checks this method.
  def supports_reactions?
    true
  end
end
