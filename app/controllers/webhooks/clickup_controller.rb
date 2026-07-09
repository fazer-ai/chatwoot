class Webhooks::ClickupController < ActionController::API
  # ClickUp signs each webhook with an HMAC-SHA256 over the raw request body
  # using the secret we stored in `CLICKUP_WEBHOOK_SECRET` at registration
  # time. Reject anything we can't verify — it's either misconfiguration or a
  # spoof attempt. Return :unauthorized (not :forbidden) so ClickUp treats the
  # webhook as "not delivered" and retries with the correct signature next time.
  before_action :verify_signature!, only: :process_payload

  def process_payload
    # ClickUp is chatty (a task edit can fan out several events); we defer the
    # actual work to a service call that walks history_items and applies only
    # what we care about. Everything else is dropped silently.
    Webhooks::Clickup::ProcessEventService.new(params.to_unsafe_h).perform
    head :ok
  end

  private

  def verify_signature!
    secret = InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_SECRET')&.value.to_s
    signature = request.headers['X-Signature'].to_s
    return head :unauthorized if secret.blank? || signature.blank?

    computed = OpenSSL::HMAC.hexdigest('sha256', secret, request.raw_post)
    return if ActiveSupport::SecurityUtils.secure_compare(signature, computed)

    head :unauthorized
  end
end
