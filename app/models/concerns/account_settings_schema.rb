module AccountSettingsSchema
  extend ActiveSupport::Concern

  SETTINGS_PARAMS_SCHEMA = {
    'type': 'object',
    'properties':
      {
        'auto_resolve_after': { 'type': %w[integer null], 'minimum': 10, 'maximum': 1_439_856 },
        'auto_resolve_message': { 'type': %w[string null] },
        'auto_resolve_ignore_waiting': { 'type': %w[boolean null] },
        'audio_transcriptions': { 'type': %w[boolean null] },
        'auto_resolve_label': { 'type': %w[string null] },
        'keep_pending_on_bot_failure': { 'type': %w[boolean null] },
        'hide_agent_unassigned_tab': { 'type': %w[boolean null] },
        'hide_agent_all_tab': { 'type': %w[boolean null] },
        'captain_auto_resolve_mode': { 'type': %w[string null], 'enum': ['evaluated', 'legacy', 'disabled', nil] },
        'conversation_required_attributes': {
          'type': %w[array null],
          'items': { 'type': 'string' }
        },
        'captain_models': {
          'type': %w[object null],
          'properties': {
            'editor': { 'type': %w[string null] },
            'assistant': { 'type': %w[string null] },
            'copilot': { 'type': %w[string null] },
            'label_suggestion': { 'type': %w[string null] },
            'audio_transcription': { 'type': %w[string null] },
            'help_center_search': { 'type': %w[string null] }
          },
          'additionalProperties': false
        },
        'captain_features': {
          'type': %w[object null],
          'properties': {
            'editor': { 'type': %w[boolean null] },
            'assistant': { 'type': %w[boolean null] },
            'copilot': { 'type': %w[boolean null] },
            'label_suggestion': { 'type': %w[boolean null] },
            'audio_transcription': { 'type': %w[boolean null] },
            'help_center_search': { 'type': %w[boolean null] }
          },
          'additionalProperties': false
        },
        # Per-account Disparador (Beta 0) rule bindings. Permissive on purpose:
        # an unset key falls back to the engine default in Disparos::RulesConfig,
        # so a partial config must validate. Each binding is optional/nullable.
        'disparador_settings': {
          'type': %w[object null],
          'properties': {
            'opt_out_label': { 'type': %w[string null] },
            # Items may arrive as strings (UI) or integers (super-admin form); RulesConfig
            # coerces them to strings for the jsonb-text comparison.
            'kanban_opt_out_steps': { 'type': %w[array null], 'items': { 'type': %w[string integer] } },
            'opt_out_lgpd_key': { 'type': %w[string null] },
            'followup_locked_key': { 'type': %w[string null] },
            'window_closes_at_key': { 'type': %w[string null] },
            'kanban_step_key': { 'type': %w[string null] },
            'whatsapp_invalid_at_key': { 'type': %w[string null] },
            'dedup_window_days': { 'type': %w[integer null] },
            'whatsapp_invalid_window_days': { 'type': %w[integer null] }
          },
          'additionalProperties': true
        }
      },
    'required': [],
    'additionalProperties': true
  }.to_json.freeze
end
