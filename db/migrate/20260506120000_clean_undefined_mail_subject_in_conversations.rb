class CleanUndefinedMailSubjectInConversations < ActiveRecord::Migration[7.1]
  # A frontend bug appended `additional_attributes[mail_subject]` unconditionally
  # via FormData, writing the literal string "undefined" when the field was
  # absent. Strip those bogus values so search results stop rendering
  # "Subject: undefined".
  def up
    execute(<<~SQL.squish)
      UPDATE conversations
      SET additional_attributes = additional_attributes - 'mail_subject'
      WHERE additional_attributes->>'mail_subject' = 'undefined'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
