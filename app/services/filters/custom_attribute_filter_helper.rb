module Filters::CustomAttributeFilterHelper
  def custom_attribute_query(query_hash, custom_attribute_type, current_index)
    @attribute_key = query_hash[:attribute_key]
    @custom_attribute_type = custom_attribute_type
    attribute_data_type
    return '' if @custom_attribute.blank?

    build_custom_attr_query(query_hash, current_index)
  end

  private

  def attribute_model
    @attribute_model = @custom_attribute_type.presence || self.class::ATTRIBUTE_MODEL
  end

  def attribute_data_type
    attribute_type = custom_attribute(@attribute_key, @account, attribute_model).try(:attribute_display_type)
    @attribute_data_type = self.class::ATTRIBUTE_TYPES[attribute_type]
  end

  def build_custom_attr_query(query_hash, current_index)
    filter_operator_value = filter_operation(query_hash, current_index)
    data_type = attribute_data_type
    table_name = attribute_model == 'conversation_attribute' ? 'conversations' : 'contacts'
    attribute_expression = data_type == 'text' ? "LOWER(#{table_name}.custom_attributes ->> ?)" : "(#{table_name}.custom_attributes ->> ?)"

    condition = ActiveRecord::Base.sanitize_sql_array(
      ["#{attribute_expression}::#{data_type} #{filter_operator_value}", @attribute_key]
    )
    condition += not_in_custom_attr_query(table_name, query_hash, data_type)

    # The condition is wrapped so the optional `OR ... IS NULL` clause stays scoped to this attribute
    # instead of spilling over the query operator that chains it to the next condition.
    "(#{condition}) #{query_hash[:query_operator]} "
  end

  def custom_attribute(attribute_key, account, custom_attribute_type)
    current_account = account || Current.account
    attribute_model = custom_attribute_type.presence || self.class::ATTRIBUTE_MODEL
    @custom_attribute = current_account.custom_attribute_definitions.where(
      attribute_model: attribute_model
    ).find_by(attribute_key: attribute_key)
  end

  def not_in_custom_attr_query(table_name, query_hash, attribute_data_type)
    return '' unless query_hash[:filter_operator] == 'not_equal_to'

    ActiveRecord::Base.sanitize_sql_array(
      [" OR (#{table_name}.custom_attributes ->> ?)::#{attribute_data_type} IS NULL ", @attribute_key]
    )
  end
end
