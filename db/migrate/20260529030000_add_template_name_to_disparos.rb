class AddTemplateNameToDisparos < ActiveRecord::Migration[7.1]
  def change
    add_column :disparos, :template_name, :string, null: true
  end
end
