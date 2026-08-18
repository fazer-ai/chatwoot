# Whether a contact is the WhatsApp account this inbox is connected as.
#
# There are two ways to be it and both have to be tried. The phone number the operator
# configured, compared through the normalizers because WhatsApp reports a Brazilian line
# with or without its ninth digit depending on when it was registered. And the LID, which
# for an account WhatsApp has not disclosed the number of is the only identity a group
# roster carries: comparing phone numbers there compares nil to something and answers no
# to "is this us?", which is how an inbox that administers an announcement-only group
# ends up refusing to post in it.
module Whatsapp::Session::Owner
  module_function

  def owns?(channel, contact)
    return false if contact.blank?
    return true if Whatsapp::Session::PhoneMatch.same_number?(contact.phone_number, channel.phone_number)

    lid = channel.provider_connection['lid'].presence
    lid.present? && contact.identifier == "#{lid}@lid"
  end
end
