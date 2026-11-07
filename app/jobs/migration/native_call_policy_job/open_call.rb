# The calls table, read without Enterprise's Call model, which a CE install does not load: the
# rows exist only where Enterprise once ran, and Migration::NativeCallPolicyJob has to end the
# connector's open ones either way.
class Migration::NativeCallPolicyJob::OpenCall < ApplicationRecord
  self.table_name = 'calls'
  belongs_to :message, optional: true
  belongs_to :conversation
end
