class EnqueueZapiWebhookUrlJob < ActiveRecord::Migration[7.1]
  def up
    Migration::ZapiWebhookUrlJob.perform_later
  end

  def down; end
end
