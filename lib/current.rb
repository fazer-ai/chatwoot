module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # Set to true while ingesting backfilled WhatsApp messages via the Baileys
  # history-sync flow. Models check this to suppress live-only side effects
  # (event dispatch, automation, notifications, outbound webhooks, read
  # receipts) that would either spam users or fire incorrectly for messages
  # that are days/weeks old.
  thread_mattr_accessor :history_import

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.history_import = nil
  end
end
