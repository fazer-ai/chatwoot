# The company half of the import's contact clock.
#
# Live traffic rolls a contact's activity up to its company through Contact's own
# after_update_commit. The import writes with `update_columns`, which skips every callback
# on purpose, so the roll-up is asked for here rather than inherited.
#
# `record_activity_at!` is the company's own rule and already refuses to move backwards,
# which is what history needs: a company somebody is talking to today keeps its clock.
module Enterprise::Import::HistorySettlement
  private

  def roll_up(contact, at)
    contact.company&.record_activity_at!(at)
  end
end
