# Settings an operator types, read strictly.
#
# Every one of these arrives as a string from the environment, and every lenient reading of
# one fails in the expensive direction on this import.
#
#   `to_f` and `to_i` answer a typo with zero, and zero reads as an instruction to each
#   setting that takes a number: no budget stops before importing anything, no `LIMIT`
#   stops at the first message, and no load ceiling never finds room, so the run pauses
#   against a load average that is never zero and stands there until somebody looks.
#
#   `ActiveModel::Type::Boolean` answers anything outside its own false list with true --
#   `no` and `flase` included -- so `ATTACHMENTS=no` starts mirroring hundreds of gigabytes
#   and `RESET_CURSOR=no` throws away the resume point, both while doing exactly the
#   opposite of what was typed.
#
# So the words are listed rather than inferred, and anything else raises before the run
# connects to anything. Shared by the two tasks because they take the same settings and a
# copy in each would drift.
module Import::Options
  TRUE_WORDS = %w[1 true t yes y on sim s].freeze
  FALSE_WORDS = %w[0 false f no n off nao não].freeze

  module_function

  def boolean(key, default: false)
    raw = ENV[key].presence
    return default if raw.nil?

    word = raw.to_s.strip.downcase
    return true if TRUE_WORDS.include?(word)
    return false if FALSE_WORDS.include?(word)

    raise ArgumentError, "#{key}: use #{TRUE_WORDS.first} ou #{FALSE_WORDS.first}, veio #{raw.inspect}"
  end

  # A count. Fractions are refused rather than truncated: `SAMPLE=0.5` truncates to zero and
  # the scan classifies nothing while reporting a finished projection.
  def integer(key, default: nil)
    parse(key, default) { |raw| Integer(raw, exception: false) }
  end

  # A measurement -- bytes, or a load average -- where a fraction is meaningful.
  def decimal(key, default: nil)
    parse(key, default) { |raw| Float(raw, exception: false) }
  end

  def parse(key, default)
    raw = ENV[key].presence
    return default if raw.nil?

    value = yield(raw)
    raise ArgumentError, "#{key}: use um numero positivo, veio #{raw.inspect}" if value.nil? || !value.positive?

    value
  end
end
