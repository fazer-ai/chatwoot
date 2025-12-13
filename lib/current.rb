module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  thread_mattr_accessor :fazer_ai_trusted_subscription_update
  thread_mattr_accessor :fazer_ai_subscription_data

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.fazer_ai_trusted_subscription_update = nil
    Current.fazer_ai_subscription_data = nil
  end

  def self.set(attributes = {})
    old_values = {}
    attributes.each do |key, value|
      old_values[key] = send(key)
      send("#{key}=", value)
    end
    yield
  ensure
    old_values.each do |key, value|
      send("#{key}=", value)
    end
  end
end
