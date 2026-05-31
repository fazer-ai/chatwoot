class AddConfigFingerprintToDisparoAudienceSnapshots < ActiveRecord::Migration[7.1]
  def change
    # config_fingerprint: a deterministic hash over the disparo's config dims
    # (template_name, template_category, audience_filter, sorted inbox_ids,
    # conversation_status) captured when the dry-run snapshot is written. ShadowRun
    # validates the disparo's CURRENT fingerprint against the approved snapshot's
    # so an operator cannot approve one preview and persist a different set after
    # the config/data changed. Nullable so older snapshots stay readable.
    add_column :disparo_audience_snapshots, :config_fingerprint, :string
  end
end
