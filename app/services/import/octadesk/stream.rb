require 'English'
require 'oj'
require 'shellwords'

# Reads a MongoDB extended-JSON export one top-level object at a time.
#
# The export is a handful of zip archives holding a JSON array per part, and the parts run
# to a gigabyte each, and a ticket collection runs to a dozen or more of them.
# `JSON.parse` on that is an out-of-memory error, and a line reader does not work either
# because the array is pretty-printed across lines. So the file is streamed through Oj's
# SAJ callbacks and rebuilt one element at a time, which keeps exactly one ticket in
# memory no matter how large the part is.
#
# Decompressed through `unzip -p` rather than a gem: there is no zip library in the
# bundle, the archives are plain deflate, and a pipe streams where a gem would want the
# member on disk first. That costs a subprocess per part and saves the whole export in
# scratch space.
class Import::Octadesk::Stream
  # Rebuilds values as the parser walks them, emitting whole objects at the point the
  # nesting returns to the top level.
  #
  # The subtlety worth naming, because getting it wrong is silent: a value's key has to be
  # captured *before* it leaves the key stack. Reading `keys.last` after popping yields the
  # parent's key instead, which attaches every nested array to the wrong name -- an object
  # that parses without error and quietly has no `Interactions`.
  class Builder < Oj::Saj
    def initialize(&on_object)
      super()
      @on_object = on_object
      @depth = 0
      @stack = []
      @keys = []
    end

    def hash_start(key)
      @depth += 1
      @stack.push({})
      @keys.push(key)
    end

    def hash_end(_key)
      object = @stack.pop
      own = @keys.pop
      @depth -= 1
      return @on_object.call(object) if @depth.zero?

      attach(object, own)
    end

    def array_start(key)
      @stack.push([])
      @keys.push(key)
    end

    def array_end(_key)
      array = @stack.pop
      attach(array, @keys.pop)
    end

    def add_value(value, key) = attach(value, key)

    private

    # Nil key inside an array, where position is the only name a value has.
    def attach(value, key)
      parent = @stack.last
      return if parent.nil?

      parent.is_a?(Array) ? parent << value : parent[key] = value
    end
  end

  def initialize(zip_path)
    @zip_path = zip_path
  end

  # Member names in the archive, in order. A listing that fails is a setup problem -- a
  # corrupt archive, a path that is not one, no `unzip` on the box -- and raises, because
  # the alternative is an empty list that walks nothing and reports the export exhausted.
  def parts
    @parts ||= begin
      listing = `unzip -Z1 #{Shellwords.escape(@zip_path)}`
      raise "cannot read the archive at #{@zip_path}" unless $CHILD_STATUS.success?

      listing.split("\n").grep(/\.json\z/).sort
    end
  end

  # Yields every object in one member. `StopIteration` from the block ends the read
  # cleanly, which is what a `LIMIT` on the task raises.
  def each_object(part, &)
    IO.popen(['unzip', '-p', @zip_path, part], 'rb') do |io|
      Oj.saj_parse(Builder.new(&), io)
    rescue StopIteration
      nil
    end
  end

  # Mongo extended JSON wraps its scalars. These are the two shapes this export uses.
  def self.oid(value) = value.is_a?(Hash) ? (value.dig('$binary', 'base64') || value['$oid']) : value
  def self.time(value) = (Time.zone.parse(value['$date']) if value.is_a?(Hash) && value['$date'].present?)
end
