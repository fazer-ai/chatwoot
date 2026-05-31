class AddTemplateCategoryToDisparos < ActiveRecord::Migration[7.1]
  def change
    # template_category: the Meta template category, used to decide whether the
    # MARKETING cross-template cooldown applies in the EligibilityEngine.
    #   0 = marketing, 1 = utility (default), 2 = authentication.
    # Defaults to utility so existing rows keep the (non-marketing) behavior and
    # the marketing cooldown stays off until explicitly opted in.
    add_column :disparos, :template_category, :integer, null: false, default: 1
  end
end
