# frozen_string_literal: true

# One JSON column with several writers, and a read-modify-write that spans a network call: the
# copy in memory is already old by the time it is written back, so whatever landed in the row
# during the call is erased, and whatever was deleted comes back. Not a database race, which is
# why it reproduces with no threads at all.
#
# Every caller here is the same shape: read the row, go to the network, write. This re-reads
# under the row lock and merges only the keys being written. The lock covers the read and the
# write and never the call itself, because a lock held across a network round trip is a worse
# problem than the one it would solve.
#
# The lock is taken on a freshly loaded row rather than through `with_lock`, which reloads the
# receiver and raises outright when it has unsaved changes. That is not a corner case here: a
# Conversation carries a dirty `display_id` from the moment it is created, on purpose, because
# `load_attributes_created_by_db_triggers` reads the trigger's value without reloading so the
# dispatcher still sees `previous_changes`. So the receiver is left untouched, and a caller that
# needs the merged value afterwards has to read it back.
module AdditionalAttributesMerge
  extend ActiveSupport::Concern

  # `attributes` carries the other columns that belong to the same write. It is not a
  # convenience: taking the lock reloads the row, which drops anything unsaved on this object,
  # so a caller that also sets `name` has to hand it over rather than assign it beforehand.
  #
  # `under` writes inside a nested hash and leaves its siblings alone, which is what the CRM
  # writers need: merging their one key at the top level would replace the whole per-CRM hash.
  #
  # Keys are stringified on the way in. The column stringifies them anyway when it serialises,
  # so a symbol merged over a string spelling of the same key would arrive as one key with the
  # last value silently winning, and which one is last is not something a caller should have to
  # know.
  #
  # A row that disappeared during the call is not an error. Every caller is enrichment after a
  # network round trip, and before this existed the write simply matched zero rows and the job
  # ended clean; raising here would turn a deleted contact into a job that retries until it
  # gives up.
  def merge_additional_attributes!(merge: {}, remove: [], under: nil, attributes: {})
    self.class.transaction do
      row = self.class.lock.find(id)
      stored = merged_attributes(row.additional_attributes, merge: merge, remove: remove, under: under)

      params = attributes.to_h.merge(additional_attributes: stored)
      next false if params.all? { |name, value| row[name] == value }

      row.update!(params)
    end
  rescue ActiveRecord::RecordNotFound
    false
  end

  private

  def merged_attributes(current, merge:, remove:, under:)
    stored = (current || {}).deep_dup
    removals = Array(remove).map(&:to_s)
    return stored.except(*removals).merge(merge.deep_stringify_keys) if under.blank?

    key = under.to_s
    # A value that is not a hash is not a namespace, whatever it is: replacing it is the only
    # way to write inside it. But do not invent one for a write that has nothing to put there,
    # or clearing a key out of a namespace that never existed would seed an empty one.
    nested = stored[key].is_a?(Hash) ? stored[key] : {}
    nested = nested.except(*removals).merge(merge.deep_stringify_keys)
    stored[key] = nested unless nested.empty? && !stored[key].is_a?(Hash)
    stored
  end
end
