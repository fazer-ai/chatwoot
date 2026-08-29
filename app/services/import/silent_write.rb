# Marks a stretch of work as "writing history", which is not the same as receiving it.
#
# An imported message goes through the same writers a live one does, and that is the
# point: what is stored must not depend on when it was imported. What must not run is
# everything a live message *sets off*. A year of history replayed through the ordinary
# path would notify every agent, fire every automation, post every outgoing webhook, wake
# the bots, reopen conversations somebody resolved months ago and send out-of-office
# replies for messages that were answered long ago.
#
# One thing does have to run, though, and it is why this has two levels rather than a
# boolean. Somebody pressed a button and is watching a screen. An unattended bulk import
# never wants this and stays `:silent` throughout; the level exists for the on-demand case. A gap thread that lands in
# the queue while the list shows the queue from before the import is a thread nobody works
# until they happen to reload, which defeats the point of importing it. So the gap half of
# a run is written in `:announce`, where the dashboard push survives and everything else
# is still suppressed, and the archive half stays `:silent`: eight hundred backdated rows
# have nothing to tell an operator now, and pushing one cable frame per row would be a
# flood aimed at every agent in the account.
#
# Three guards read this flag, all declared in config/initializers/import_guards.rb:
#
#   AsyncDispatcher#dispatch                 the listeners that act on the world:
#                                            automations, campaigns, CSAT, webhooks,
#                                            notifications, reporting, the outgoing
#                                            channel. Never reached, at either level
#   SyncDispatcher#dispatch                  ActionCableListener (the dashboard push) and
#                                            AgentBotListener. Under `:announce` the cable
#                                            listener runs and the bot does not
#   Message#execute_after_create_commit_callbacks
#                                            the side effects that are not events: reopen,
#                                            message templates, the reply send, and the
#                                            activity stamps the importer sets itself.
#                                            Under `:announce` it re-emits `message.created`
#                                            on its own, so the thread an operator has open
#                                            fills in rather than only the list card
#
# Scoped to the thread rather than to a request: the importer runs inside a Sidekiq job,
# and the flag must not leak into whatever that worker picks up next.
module Import::SilentWrite
  KEY = :import_silent_write

  module_function

  # Nested calls are safe: the previous value is restored rather than cleared, so an
  # importer running inside another silenced block does not un-silence it on the way out.
  # That restore is what lets the gap run raise the level for its own stretch and hand the
  # archive level back afterwards, inside one enclosing `wrap`.
  def wrap(announce: false)
    previous = ActiveSupport::IsolatedExecutionState[KEY]
    ActiveSupport::IsolatedExecutionState[KEY] = announce ? :announce : :silent
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[KEY] = previous
  end

  def on?
    ActiveSupport::IsolatedExecutionState[KEY].present?
  end

  # Whether this stretch may reach the dashboard. Only ever true inside `on?`, so a guard
  # that checks it still has to check `on?` first to tell "importing, announcing" from
  # "not importing at all", which is the ordinary case and must go through untouched.
  def announce?
    ActiveSupport::IsolatedExecutionState[KEY] == :announce
  end
end
