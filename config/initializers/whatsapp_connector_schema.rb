# The schema the embedded WhatsApp connector keeps its store in (whatsapp_connector) is
# created like any other part of the database: by its migration, and by db/schema.rb on a
# fresh database, which Rails dumps as `create_schema "whatsapp_connector"`. Both go
# through here.
#
# A database role that may create tables but not schemas would otherwise have its whole
# install or upgrade stopped by an optional channel. For this one schema, that refusal is a
# warning instead: everything else in Chatwoot works, and the connector's start says the
# schema is missing and the statement that creates it. Any other error, and any other
# schema, still raises.
module WhatsappConnectorSchema
  NAME = 'whatsapp_connector'.freeze

  # In a savepoint, so a refusal inside a migration's transaction does not abort it.
  def create_schema(schema_name, **options)
    transaction(requires_new: true) { super }
  rescue ActiveRecord::StatementInvalid => e
    raise unless schema_name.to_s == NAME && e.cause.is_a?(PG::InsufficientPrivilege)

    Rails.logger.warn(
      "Could not create schema #{NAME} (#{e.cause.message.strip}). The WhatsApp (native) connector will not " \
      "start until it exists: CREATE SCHEMA #{NAME} AUTHORIZATION <the database user Chatwoot connects as>"
    )
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) { prepend WhatsappConnectorSchema }
