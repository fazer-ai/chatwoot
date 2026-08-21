# Reports jobs that exhausted their retries and landed in the dead set.
#
# Until this existed nothing watched that set, so a send that failed every attempt was
# discovered by the customer complaining rather than by monitoring — the dead set held
# hundreds of SendReplyJob failures nobody had been told about. The handler runs for
# every job class; SendReplyJob additionally resolves the message so the report names the
# account, inbox and conversation instead of an opaque id.
class SidekiqDeathHandler
  def self.call(job, exception)
    new(job, exception).report
  end

  def initialize(job, exception)
    @job = job
    @exception = exception
  end

  def report
    Rails.logger.error(
      "[SIDEKIQ][DEAD] #{job_class} jid=#{@job['jid']} queue=#{@job['queue']} " \
      "error=#{@exception.class}: #{@exception.message}#{context_suffix}"
    )
    ChatwootExceptionTracker.new(@exception, account: account).capture_exception
  rescue StandardError => e
    # A death handler that raises takes the reporting down with the job it was reporting.
    Rails.logger.error "[SIDEKIQ][DEAD] handler failed: #{e.message}"
  end

  private

  # ActiveJob wraps the real class name; plain Sidekiq workers use 'class'.
  def job_class
    @job['wrapped'] || @job['class']
  end

  # NEVER logged, only used to resolve the message below. Arguments are job payloads:
  # WebhookJob carries the customer's message body and `secret: webhook.secret`
  # positionally, so dumping them here would put message content and a signing credential
  # into the log aggregator on any unexpected terminal failure. Key-based filtering does
  # not help with a bare secret in a positional array. The jid in the log line is enough to
  # pull the full payload from the dead set, where access is already controlled, and
  # ChatwootExceptionTracker ships it to Sentry with the same protection.
  def job_args
    payload = @job['args']&.first
    payload.is_a?(Hash) ? payload['arguments'] : @job['args']
  end

  def message
    return @message if defined?(@message)

    @message = job_class.to_s == 'SendReplyJob' ? Message.find_by(id: job_args&.first) : nil
  end

  def account
    message&.account
  end

  def context_suffix
    return '' if message.blank?

    " account_id=#{message.account_id} inbox_id=#{message.inbox_id} " \
      "conversation_id=#{message.conversation_id} message_id=#{message.id}"
  end
end
