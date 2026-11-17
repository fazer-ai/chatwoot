# The embedded WhatsApp connector keeps its store (pairings, Signal keys, pending history)
# in this schema of Chatwoot's own database, reached with `search_path=whatsapp_connector`
# (docker/entrypoints/helpers/whatsapp_connector.rb). Creating it here rather than when the
# connector starts means the worker never needs a privilege the rest of the app does not.
#
# A role that may migrate but not create schemas would otherwise have its whole upgrade
# stopped by an optional channel. That one case is let through with a warning: the
# connector's start then names the missing schema and the statement to create it.
class CreateWhatsappConnectorSchema < ActiveRecord::Migration[7.2]
  SCHEMA = 'whatsapp_connector'.freeze

  def up
    transaction(requires_new: true) { create_schema SCHEMA, if_not_exists: true }
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::InsufficientPrivilege)

    say "Could not create schema #{SCHEMA} (#{e.cause.message.strip}). The WhatsApp (native) connector " \
        "will not start until it exists: CREATE SCHEMA #{SCHEMA} AUTHORIZATION <the database user Chatwoot connects as>"
  end

  def down
    drop_schema SCHEMA, if_exists: true
  end
end
