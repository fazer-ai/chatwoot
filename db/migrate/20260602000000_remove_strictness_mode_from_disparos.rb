class RemoveStrictnessModeFromDisparos < ActiveRecord::Migration[7.1]
  # The strictness_mode toggle is dropped: it only gated followup_locked, which is
  # now an always-applied opt-out. The reversible down re-adds the column exactly as
  # 20260530000000 first introduced it (integer, default 0, null: false).
  def change
    remove_column :disparos, :strictness_mode, :integer, null: false, default: 0
  end
end
