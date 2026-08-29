# Whether a message's attachments are in scope, asked in one place because two callers
# have to give the same answer about the same message.
#
# The backfill asks before it fetches and the importer asks before it attaches, and the
# cost the cutoff exists to control is paid at the fetch: a policy the two read separately
# would eventually disagree, and the way it would show is a run that spends its whole
# provider budget on attachments it then declines to keep.
#
# Three states, spelled out rather than inferred from nil, because "no cutoff given" reads
# as both "all of them" and "none of them" and the two are hundreds of gigabytes apart:
#
#   :none    the default. Nothing is fetched beyond the text.
#   :all     every attachment, whatever the message's date.
#   a Time   attachments on messages newer than it, nothing older.
class Import::Email::AttachmentPolicy
  NONE = :none
  ALL = :all

  # Accepts what a caller naturally has: a symbol, a Time, or nil for the default.
  def self.build(value)
    return new(NONE) if value.blank?
    return new(ALL) if value.to_s.casecmp(ALL.to_s).zero?
    return new(NONE) if value.to_s.casecmp(NONE.to_s).zero?
    return new(value) if value.respond_to?(:to_time)

    raise ArgumentError, "attachments must be :none, :all or a time, got #{value.inspect}"
  end

  def initialize(value)
    @value = value.is_a?(Symbol) ? value : value.to_time
  end

  def none? = @value == NONE
  def all? = @value == ALL

  # An unknown date is treated as out of scope under a cutoff: the message is older than
  # nothing that can be checked, and spending the budget on a maybe is the expensive way
  # to be wrong.
  def skip?(occurred_at)
    return true if none?
    return false if all?

    occurred_at.blank? || occurred_at < @value
  end

  def to_s
    return 'nenhum' if none?
    return 'todos' if all?

    "a partir de #{@value.to_date}"
  end
end
