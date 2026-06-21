# Read + acknowledge endpoint for the operations notification center.
# Notifications are CREATED only via super admin (see
# `SuperAdmin::OperationsNotificationsController`); regular users only LIST
# and ACK them.
class Api::V1::Accounts::OperationsNotificationsController < Api::V1::Accounts::BaseController
  before_action :fetch_notification, only: [:acknowledge]

  # Top of the inbox bell — "Central de Notificação" listing.
  # Returns up to 10 most-recent visible notifications, with `acknowledged_at`
  # populated when the current user has already dismissed them.
  def index
    notifications = OperationsNotification.visible_for(current_user, current_account).limit(10).to_a
    @notifications = decorate_with_acks(notifications)
  end

  # What the modal asks for on login + polling: only those NOT yet acked.
  def pending
    notifications = OperationsNotification.pending_for(current_user, current_account)
                                          .order(severity: :desc, created_at: :desc)
                                          .to_a
    @notifications = decorate_with_acks(notifications)
  end

  # User clicks "Entendi". Idempotent — repeated calls return the existing ack.
  def acknowledge
    @ack = OperationsNotificationAck.find_or_create_by!(
      operations_notification_id: @notification.id,
      user_id: current_user.id
    ) do |ack|
      ack.account_id = current_account.id
      ack.acknowledged_at = Time.current
      ack.ip = request.remote_ip
      ack.user_agent = request.user_agent
    end
    render json: { success: true, acknowledged_at: @ack.acknowledged_at.to_i }
  end

  private

  def fetch_notification
    @notification = OperationsNotification.visible_for(current_user, current_account).find(params[:id])
  end

  def decorate_with_acks(notifications)
    return [] if notifications.empty?

    ack_lookup = OperationsNotificationAck
                 .where(operations_notification_id: notifications.map(&:id), user_id: current_user.id)
                 .index_by(&:operations_notification_id)
    notifications.map { |n| [n, ack_lookup[n.id]] }
  end
end
