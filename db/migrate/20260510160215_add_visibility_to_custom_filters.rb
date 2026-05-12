class AddVisibilityToCustomFilters < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_filters, :visibility, :integer, default: 0, null: false
    add_index :custom_filters,
              [:account_id, :filter_type, :visibility, :user_id],
              name: 'index_custom_filters_on_account_type_visibility_user'
  end
end
