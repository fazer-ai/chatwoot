class AddVisibilityToCustomFilters < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_filters, :visibility, :integer, default: 0, null: false
  end
end
