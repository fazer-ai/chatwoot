# Central mapping of every ClickUp id the Feedback ticket flow depends on:
# the workspace (team) id, the target Feedback list id, and every custom
# field / dropdown option id we read from or write to.
#
# Anything ClickUp-side that changes — renamed field, new dropdown option,
# migrated list — lives here and only here. All the jobs and services
# reference this module so a re-map is a single-file change.
#
# These ids are static for the Auris ClickUp workspace and are not
# user-configurable at the moment. When we ship Phase 2 (multiple ticket
# types, admin-defined field mapping) this whole module moves into the
# `ticket_types.field_mapping` JSON.
module Integrations::Clickup::FieldMap
  TEAM_ID = '90132001451'.freeze
  FEEDBACK_LIST_ID = '901327397266'.freeze

  # Custom field ids on the Feedback list. Keys mirror the ClickUp field
  # names so the debug output is human-readable.
  FIELDS = {
    ambiente: '1a37d33d-8b7d-4361-b554-c21b848ea2dc',
    canal: 'a98f0069-f0ad-48c9-b5d8-231789e08ef3',
    chat_id: '01924c91-ab09-4b51-9781-43a7953c699e',
    comportamento_esperado: '9b7540cd-4861-4c88-8e14-3171614e5cc8',
    contexto: '84a863c5-50a1-4846-88fa-0befea67f9ae',
    user_id: 'b9bf4453-847e-48da-9d2f-d90f88a923a4',
    user_name: 'de5fdd9f-fe9f-4467-847c-b6051f01224f',
    account_id: '79c64ab5-1de8-4418-bdac-7017b905c8a6',
    aurischat_url: '34c5320c-8246-4502-9069-2143673f472b',
    relatar_problema: '32dff85f-8a96-4fb5-b0d0-3fd7f02b58ab',
    resposta_para_cliente: '50570ced-f352-486f-b03e-dfde3e8549a2'
  }.freeze

  # Ambiente dropdown option ids. We pick between them based on the
  # FRONTEND_URL env var so the ops team can filter by production vs
  # homolog without the operator having to select the environment.
  AMBIENTE_OPTIONS = {
    producao: '5bf5e73f-c958-4803-83c3-b7c94768d27e',
    homologacao: '2bb0d18a-85cd-43f9-a637-c242df98c6d7'
  }.freeze

  # Canal dropdown option ids. WhatsApp is sub-mapped by provider because
  # the ClickUp side splits Cloud API / Baileys / Z-API into their own
  # options (and the ops workflow depends on that distinction).
  CANAL_OPTIONS = {
    'Channel::Whatsapp' => {
      # `Channel::Whatsapp#provider` values.
      'whatsapp_cloud' => 'bdc6ecc8-36d7-4f4f-8b65-ec4b49918e95',
      'baileys' => 'f574e517-4c63-4861-a320-4db73069e145',
      'zapi' => '62fb117d-0986-40bc-8451-7e4fc1472068'
    }.freeze,
    'Channel::Instagram' => '6b5c5831-d2d4-4f3f-8396-3bde2845ef27',
    'Channel::FacebookPage' => '48f17a7e-16e4-46cb-9ab0-997964a456bf',
    'Channel::Simulator' => 'd39c9d92-a85a-4353-bde0-4ec675a15bee'
  }.freeze

  # Contexto dropdown option ids. Phase 1 always uses "Mensagem" (the
  # feedback button lives on a message); the "Conversa" option is here for
  # Phase 2 when we let the operator open a ticket from the conversation
  # header.
  CONTEXTO_OPTIONS = {
    conversa: '721296a2-2139-45de-a195-3d09d3003624',
    mensagem: '9e476afd-7811-43bd-93c5-74e3cab283df'
  }.freeze

  # ClickUp events we subscribe to. `taskStatusUpdated` drives the status
  # column in Meus Tickets; `taskCustomFieldUpdated` flows the ops team's
  # "Resposta para o Cliente" back into the ticket.
  WEBHOOK_EVENTS = %w[taskStatusUpdated taskCustomFieldUpdated].freeze

  # ClickUp status ids on the Feedback list that trigger a bell + toast
  # notification for the ticket owner. Every other status change updates
  # the ticket silently — Meus Tickets refreshes via ActionCable but no
  # noisy popup fires. These slugs are the ClickUp `status.status` string
  # (lowercased) so the mapping survives a rename of the display label.
  NOTIFIABLE_STATUS_SLUGS = %w[resolvido restrição encerrado].freeze

  # ClickUp `status.type` for a status the ticket is done under, used to
  # detect "close" transitions when the status slug differs from the ones
  # above (e.g. custom "Cancelado" status added later).
  TERMINAL_STATUS_TYPES = %w[closed done].freeze

  # -- helpers --------------------------------------------------------

  # Prod install if the panel URL is chat.auris.ia.br, everything else
  # (homolog / worktrees / dev on localhost) maps to Homologação. Keeps
  # the ops team from having to filter test noise out of production
  # queries.
  def self.ambiente_option_for(frontend_url)
    prod = frontend_url.to_s.start_with?('https://chat.auris.ia.br')
    prod ? AMBIENTE_OPTIONS[:producao] : AMBIENTE_OPTIONS[:homologacao]
  end

  # Resolves the canal option id for a given inbox. WhatsApp inboxes fan
  # out on `channel.provider`. Returns nil when the inbox uses a channel
  # we haven't mapped (e.g. Line, Telegram) so the caller can drop the
  # field from the payload instead of failing the task creation.
  def self.canal_option_for(inbox)
    return nil unless inbox

    mapping = CANAL_OPTIONS[inbox.channel_type]
    return nil if mapping.blank?
    return mapping if mapping.is_a?(String)

    provider = inbox.channel.try(:provider)
    mapping[provider]
  end
end
