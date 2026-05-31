# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — Audience Resolver.
#
# Single responsibility: fetch the CANDIDATE conversations for a dispatch by
# Stage (kanban_step) and/or labels, scoped to one account. This is the
# candidate-fetch step only.
#
# SINGLE-ENFORCEMENT-POINT RULE (do not break this): the resolver MUST NOT
# discard candidates for any reason other than the stage/label filter. It does
# NOT exclude conversations whose contact has a missing/invalid phone, whose
# inbox/provider is incompatible, that are opt-out, Stage-9,
# `agente-off-permanente` or `opt_out_lgpd`. All those become *skipped targets*
# later in the Eligibility Engine. If the resolver dropped them they could never
# appear as skipped targets and parity vs wf15 would break.
#
# Kanban "Stage" is NOT a table/association in this fork: it lives in
# `conversations.custom_attributes` under the frozen contract key `kanban_step`
# (set by external n8n workflows). The key is a constant (safe SQL literal);
# only the requested values are bound. `->>` extracts text, so values are
# compared as strings.
#
# Filter input (plain hash or anything responding to []), Beta 0 supports:
#   - kanban_steps: array of stage values (optional)
#   - label:        array of label titles (optional)
# At least one must be present, otherwise InvalidAudienceFilter is raised.
#
# Semantics:
#   - both given  -> AND (conversation matches a requested stage AND carries at
#     least one of the requested labels)
#   - one given   -> filter by that one
# Labels use acts-as-taggable-on with `any: true` (matches ConversationFinder
# and Label#conversations). Label titles are stored downcased.
#
# wf15 reconciliation (supersedes the earlier "audience is NOT scoped to selected
# inboxes" contract): per the wf15 reconciliation + product decision, the
# operator-SELECTED inbox(es) DO scope the audience.
#   - inbox_ids: the disparo's selected disparo_inboxes inbox ids. A disparo
#     always has >=1 disparo_inbox, so this is REQUIRED; a blank set raises
#     InvalidAudienceFilter (an unscoped account-wide audience is never intended).
#   - conversation_status: 'open' keeps only conversations.status == open; 'all'
#     applies no status filter. Defaults to :all at the resolver level; the
#     services pass the disparo's configured value.
# These narrow the audience but the resolver still does NOT discard by
# phone/provider/opt-out — those stay in the EligibilityEngine.
#
# Return value: an ActiveRecord::Relation of Conversation scoped to the account,
# with `contact` preloaded (`.includes(:contact)`) and the `inbox`'s polymorphic
# `channel` preloaded (`.preload(inbox: :channel)`), de-duplicated (`.distinct`)
# so the grain is one row per matching conversation. The inbox/channel preload
# avoids an N+1 because the EligibilityEngine reads `conversation.inbox.channel`
# (and the channel's `message_templates` jsonb column) per candidate; `preload`
# (not `includes`) is used for the polymorphic `channel` so Rails never attempts
# a JOIN-based eager load (which raises EagerLoadPolymorphicError). Each
# conversation exposes `id` (conversation_id) and `contact_id` / `contact`. The
# Eligibility Engine iterates this relation; the resolver itself never writes to
# the DB.
class Disparos::AudienceResolver
  def initialize(account:, filter:, inbox_ids:, conversation_status: :all)
    @account = account
    @kanban_steps = Array(filter[:kanban_steps]).compact
    @labels = Array(filter[:label]).compact
    @inbox_ids = Array(inbox_ids).compact
    @conversation_status = conversation_status.to_s
  end

  def perform
    validate_filter!

    scope = @account.conversations.where(inbox_id: @inbox_ids)
    scope = scope.where(status: :open) if @conversation_status == 'open'
    scope = scope.where("conversations.custom_attributes ->> 'kanban_step' IN (?)", @kanban_steps.map(&:to_s)) if @kanban_steps.present?
    scope = scope.tagged_with(@labels, any: true) if @labels.present?
    scope.includes(:contact).preload(inbox: :channel).distinct
  end

  private

  def validate_filter!
    raise CustomExceptions::Disparos::InvalidAudienceFilter if @inbox_ids.blank?
    return if @kanban_steps.present? || @labels.present?

    raise CustomExceptions::Disparos::InvalidAudienceFilter
  end
end
