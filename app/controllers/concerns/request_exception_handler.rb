module RequestExceptionHandler
  extend ActiveSupport::Concern

  QUERY_CANCELED_ERROR_MESSAGE_PATTERNS = [
    'ActiveRecord::QueryCanceled',
    'PG::QueryCanceled',
    'canceling statement due to statement timeout'
  ].freeze

  included do
    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from CustomExceptions::Inbox::LimitExceeded,
                CustomExceptions::Account::EmailLimitExceeded,
                CustomExceptions::Conversation::AlreadyAssigned,
                with: :render_error_response
  end

  # Exceptions whose message describes our own code instead of answering the caller.
  # `undefined method 'to_h' for an instance of String` tells whoever sent the request nothing
  # and tells them how the builder is written. They reach HTTP bodies through the blanket
  # `rescue StandardError` some actions need, which also shadows the handling below.
  INTERNAL_DIAGNOSIS = [NameError, TypeError, ArgumentError].freeze

  private

  # For an action that has to rescue broadly. What the caller can act on keeps its own message,
  # including the ones the app raises as a plain StandardError, which no rule by class can tell
  # from a bug. What only describes a bug is logged and answered with a sentence, and a record
  # that was not found is answered the way this concern already answers it everywhere else,
  # rather than with the SQL predicate that missed.
  def render_rescued_error(exception)
    if exception.is_a?(ActiveRecord::RecordNotFound)
      log_handled_error(exception)
      # The same answer `handle_with_exception` gives for it everywhere else, status included. A
      # record that is not there is not a refused write, and while the two paths said different
      # sentences the status was at least redundant; with one sentence it was all that separated
      # them, and it separated by who caught the exception rather than by what happened.
      return render_not_found_error('Resource could not be found')
    end

    return render_could_not_create_error(exception.message) unless INTERNAL_DIAGNOSIS.any? { |klass| exception.is_a?(klass) }

    log_unexpected_error(exception)
    render_could_not_create_error(I18n.t('errors.request.unexpected'))
  end

  # The only record of what actually happened, since the caller no longer carries it.
  def log_unexpected_error(exception)
    Rails.logger.error(
      "Unexpected error: #{exception.class}: #{exception.message}\n#{Array(exception.backtrace).first(5).join("\n")}"
    )
  end

  def handle_with_exception
    yield
  rescue ActiveRecord::RecordNotFound => e
    log_handled_error(e)
    render_not_found_error('Resource could not be found')
  rescue Pundit::NotAuthorizedError => e
    log_handled_error(e)
    render_unauthorized('You are not authorized to do this action')
  rescue ActionController::ParameterMissing => e
    log_handled_error(e)
    render_could_not_create_error(e.message)
  rescue ActiveRecord::QueryCanceled => e
    log_handled_error(e)
    render_could_not_create_error(database_query_canceled_message)
  ensure
    # to address the thread variable leak issues in Puma/Thin webserver
    Current.reset
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end

  def render_not_found_error(message)
    render json: { error: message }, status: :not_found
  end

  def render_could_not_create_error(error)
    render json: { error: sanitized_error_message(error) }, status: :unprocessable_entity
  end

  def render_payment_required(message)
    render json: { error: message }, status: :payment_required
  end

  def render_internal_server_error(message)
    render json: { error: message }, status: :internal_server_error
  end

  def render_record_invalid(exception)
    log_handled_error(exception)
    render json: {
      message: exception.record.errors.full_messages.join(', '),
      attributes: exception.record.errors.attribute_names
    }, status: :unprocessable_entity
  end

  def render_error_response(exception)
    log_handled_error(exception)
    render json: exception.to_hash, status: exception.http_status
  end

  def log_handled_error(exception)
    logger.info("Handled error: #{exception.inspect}")
  end

  def sanitized_error_message(message)
    return database_query_canceled_message if database_query_canceled_message?(message)

    message
  end

  def database_query_canceled_message?(message)
    error_message = message.to_s
    QUERY_CANCELED_ERROR_MESSAGE_PATTERNS.any? { |pattern| error_message.include?(pattern) }
  end

  def database_query_canceled_message
    I18n.t('errors.database.query_canceled')
  end
end
