# spec/enterprise/models/conversation_monitors/message_tracking_spec.rb runs without
# transactional tests and cleans up its accounts and users by hand, but not the audit rows
# that setup writes, so audit counts in specs that run after it include them. Deleted here,
# around each of its examples, since the upstream file stays as it is.
RSpec.configure do |config|
  message_tracking = { file_path: %r{spec/enterprise/models/conversation_monitors/message_tracking_spec\.rb} }

  config.before(:each, message_tracking) { @fazer_ai_ee_audit_floor = Audited::Audit.maximum(:id) || 0 }
  config.after(:each, message_tracking) { Audited::Audit.where(id: (@fazer_ai_ee_audit_floor + 1)..).delete_all }
end
