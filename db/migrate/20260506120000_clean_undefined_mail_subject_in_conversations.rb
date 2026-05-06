class CleanUndefinedMailSubjectInConversations < ActiveRecord::Migration[7.1]
  # A frontend bug appended `additional_attributes[mail_subject]` unconditionally
  # via FormData, writing the literal string "undefined" when the field was
  # absent. Strip those bogus values so search results stop rendering
  # "Subject: undefined".
  #
  # Scoped to non-email inboxes only: email channels legitimately use
  # `mail_subject`, and "undefined" could in principle be a subject the user
  # actually typed. Other channel types have no concept of subject, so the
  # value can only have come from the bug.
  def up
    execute(<<~SQL.squish)
      UPDATE conversations
      SET additional_attributes = additional_attributes - 'mail_subject'
      FROM inboxes
      WHERE conversations.inbox_id = inboxes.id
        AND inboxes.channel_type <> 'Channel::Email'
        AND conversations.additional_attributes->>'mail_subject' = 'undefined'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
