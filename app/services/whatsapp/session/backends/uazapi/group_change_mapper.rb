# What changed in a group, as this provider reports it: whatsmeow's `GroupChange` with
# every field the event did not touch left null.
#
# Which of the arrays is populated is the whole signal. There is no event type on a
# membership change, and `nil` has to keep meaning "not reported": read as `false`, an
# untouched setting would be applied as one somebody just turned off.
class Whatsapp::Session::Backends::Uazapi::GroupChangeMapper
  # Each action names the same people twice, once by number and once by LID.
  ACTIONS = %w[Join Leave Promote Demote].freeze

  attr_reader :event

  def initialize(event)
    @event = event
  end

  # Returns the canonical changes, or nil when the event reports none.
  def perform
    changes = events::GroupUpdated::Changes.new(**settings, **participants)
    changes if changes.any?
  end

  private

  def model = Whatsapp::Session::Model
  def events = Whatsapp::Session::Model::Events

  def settings
    {
      subject: nested(event[:Name], 'Name'),
      description: nested(event[:Topic], 'Topic'),
      announce: nested(event[:Announce], 'IsAnnounce'),
      locked: nested(event[:Locked], 'IsLocked'),
      join_approval: nested(event[:MembershipApprovalMode], 'IsJoinApprovalRequired')
    }
  end

  def participants
    ACTIONS.index_with { |action| parties(event[action], event["#{action}Lid"]) }
           .transform_keys { |action| action.downcase.to_sym }
  end

  # Two parallel lists describing the same people. Paired by position, which is how the
  # provider sends them; either can be the only one there.
  def parties(phones, lids)
    phones = Array(phones)
    lids = Array(lids)
    return if phones.empty? && lids.empty?

    [phones.size, lids.size].max.times.filter_map { |index| party(lids[index], phones[index]) }
  end

  def party(lid, phone)
    lid = address_id(lid)
    phone = address_id(phone)
    model::Party.new(lid: lid, phone: phone) if lid.present? || phone.present?
  end

  def address_id(jid)
    model::Address.parse(jid)&.id
  end

  # A changed field arrives either as the value itself or wrapped in the struct that
  # carries it and its metadata.
  def nested(value, key)
    value.is_a?(Hash) ? value[key] : value
  end
end
