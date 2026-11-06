# Upstream examples under spec/enterprise that cannot pass on this fork, skipped by name so the
# files themselves stay identical to upstream. Each one is replaced by a spec under
# fazer_ai_ee/spec that covers the same ground against the fork's behavior.
#
# fazer_ai_ee/spec/upstream_overrides_spec.rb checks that every entry still names an example
# upstream has, so an entry goes stale loudly when an upstream merge changes the example.
module FazerAiEe
  SUPERSEDED_UPSTREAM_EXAMPLES = {
    'spec/enterprise/models/account_saml_settings_spec.rb' => {
      'automatically generates sp_entity_id when creating' => 'fazer_ai_ee/spec/models/account_saml_settings_spec.rb'
    },
    'spec/enterprise/services/voice/call_transcription_service_spec.rb' => {
      'reindexes before broadcasting so a retry after a reindex failure does not resend the update event' =>
        'fazer_ai_ee/spec/services/voice/call_transcription_service_spec.rb'
    },
    'spec/enterprise/builders/saml_user_builder_spec.rb' => {
      'returns unsaved user object when user creation fails' => 'fazer_ai_ee/spec/builders/saml_user_builder_spec.rb',
      'does not create account association for failed user' => 'fazer_ai_ee/spec/builders/saml_user_builder_spec.rb'
    },
    'spec/enterprise/jobs/enterprise/internal/check_new_versions_job_spec.rb' => {
      'updates the plan info' => 'fazer_ai_ee/spec/jobs/internal/check_new_versions_job_spec.rb',
      'calls Internal::ReconcilePlanConfigService' => 'fazer_ai_ee/spec/jobs/internal/check_new_versions_job_spec.rb'
    },
    'spec/enterprise/models/applied_sla_spec.rb' => {
      'excludes blocked contacts and keeps conversations with missing contacts' => 'fazer_ai_ee/spec/models/sla_with_deleted_contact_spec.rb'
    },
    'spec/enterprise/models/conversation_spec.rb' => {
      'keeps existing behavior when contact is missing' => 'fazer_ai_ee/spec/models/sla_with_deleted_contact_spec.rb'
    },
    'spec/enterprise/services/conversation_monitors/evaluator_spec.rb' => {
      'holds exhausted accounts until next month and preserves full history across new input' =>
        'fazer_ai_ee/spec/services/conversation_monitors/evaluator_spec.rb',
      'preserves the monthly hold through an earlier batch provider cooldown after the reset' =>
        'fazer_ai_ee/spec/services/conversation_monitors/evaluator_spec.rb'
    }
  }.freeze
end

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/enterprise/}) do |metadata|
    file = metadata[:file_path].to_s.delete_prefix('./')
    replacement = FazerAiEe::SUPERSEDED_UPSTREAM_EXAMPLES.dig(file, metadata[:description])
    metadata[:skip] = "superseded on this fork by #{replacement}" if replacement
  end
end
