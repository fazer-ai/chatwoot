# Backs Reports::HandledConversations. A month of a busy account is over a million
# outgoing messages, and without it the agents report scans the heap for every one of
# them and runs past the statement timeout. The predicate is Reports::HandledConversations::PREDICATE,
# copied rather than referenced so this migration keeps meaning the same thing whatever
# the constant becomes; the spec on the query plan fails when the two drift apart.
#
# On a large installation, create it by hand with the same statement before deploying,
# so the migration finds it and returns at once.
class AddHandledConversationsIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :messages, [:account_id, :created_at],
              name: 'index_messages_on_handled_conversations',
              include: [:sender_type, :sender_id, :conversation_id, :inbox_id],
              where: 'message_type = 1 AND private = false ' \
                     "AND ((content_attributes#>>'{}')::jsonb->>'is_reaction' = 'true') IS NOT TRUE " \
                     "AND COALESCE((content_attributes#>>'{}')::jsonb->>'automation_rule_id', '') = '' " \
                     "AND COALESCE(additional_attributes->>'campaign_id', '') = '' " \
                     "AND (sender_type = 'User' OR COALESCE((content_attributes#>>'{}')::jsonb->>'external_echo', '') NOT IN ('', 'false'))",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
