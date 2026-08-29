# Logging a rake task into a mail channel.
#
# The same three cases the live fetch services split into, because a channel does not stop
# being an OAuth channel when a backfill is the one connecting: on Google and Microsoft the
# stored `imap_password` is empty or stale and only a refreshed XOAUTH2 token
# authenticates. Reading the column would fail every run against those providers with
# nothing but a login error to say why.
#
# Its own class because it is about credentials rather than about walking a mailbox, and
# because it is the piece a second importer would need first.
class Import::Email::Authentication
  def self.perform(imap, channel)
    case channel.provider
    when 'google'
      imap.authenticate('XOAUTH2', channel.imap_login, Google::RefreshOauthTokenService.new(channel: channel).access_token)
    when 'microsoft'
      imap.authenticate('XOAUTH2', channel.imap_login,
                        Microsoft::RefreshOauthTokenService.new(channel: channel).access_token)
    else
      Imap::Authentication.authenticate!(imap, channel.imap_authentication, channel.imap_login, channel.imap_password)
    end
  end
end
