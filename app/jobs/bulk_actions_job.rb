class BulkActionsJob < ApplicationJob
  include DateRangeHelper

  queue_as :medium
  attr_accessor :records

  MODEL_TYPE = ['Conversation'].freeze

  def perform(account:, params:, user:)
    @account = account
    Current.user = user
    @params = params
    @records = records_to_updated(params[:ids])
    bulk_update
  ensure
    Current.reset
  end

  def bulk_update
    bulk_remove_labels
    bulk_conversation_update
  end

  def bulk_conversation_update
    params = available_params(@params)
    ai_enabled = extract_ai_enabled(params)
    records.each do |conversation|
      bulk_add_labels(conversation)
      bulk_snoozed_until(conversation)
      bulk_set_ai_status(conversation, ai_enabled)
      conversation.update!(params) if params.present?
    end
  end

  # `ai_enabled` can't ride the generic `update!`: the canonical entrypoint is
  # `Conversation#set_ai_status!`, which dispatches between the legacy
  # `agente-off` label and the persisted `ai_enabled` column depending on the
  # account's mode. Pull it out of the field bag and route it ourselves.
  def extract_ai_enabled(params)
    return nil unless params&.key?('ai_enabled')

    ActiveModel::Type::Boolean.new.cast(params.delete('ai_enabled'))
  end

  def bulk_set_ai_status(conversation, ai_enabled)
    return if ai_enabled.nil?

    conversation.set_ai_status!(ai_enabled)
  end

  def bulk_remove_labels
    records.each do |conversation|
      remove_labels(conversation)
    end
  end

  def available_params(params)
    return unless params[:fields]

    params[:fields].delete_if { |key, value| value.nil? && key == 'status' }
  end

  def bulk_add_labels(conversation)
    conversation.add_labels(@params[:labels][:add]) if @params[:labels] && @params[:labels][:add]
  end

  def bulk_snoozed_until(conversation)
    conversation.snoozed_until = parse_date_time(@params[:snoozed_until].to_s) if @params[:snoozed_until]
  end

  def remove_labels(conversation)
    return unless @params[:labels] && @params[:labels][:remove]

    labels = conversation.label_list - @params[:labels][:remove]
    conversation.update!(label_list: labels)
  end

  def records_to_updated(ids)
    current_model = @params[:type].camelcase
    return unless MODEL_TYPE.include?(current_model)

    current_model.constantize&.where(account_id: @account.id, display_id: ids)
  end
end
