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
end
