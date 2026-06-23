class SuperAdmin::OperationsNotificationsController < SuperAdmin::ApplicationController
  # Notifications are *soft-deleted* (deleted_at) so the report keeps showing
  # historical acks even after the operator removes the entry from the active
  # list. The default scope is "active only" but the `deleted` filter on the
  # dashboard lets the operator browse the archived ones.

  def create
    # `current_super_admin` is the Devise helper for the super_admin scope
    # (Chatwoot stores super admins as `User`s with type='SuperAdmin', and
    # SuperAdmin < User). Using `current_user` here would be nil — that's
    # what was making the form bounce: `created_by` validation failed and
    # Administrate re-rendered the form, sometimes looking like a reload
    # loop because of the redirect-on-error path.
    resource = new_resource(resource_params.merge(
                              created_by: current_super_admin,
                              published_at: Time.current
                            ))

    if resource.save
      redirect_to(after_resource_created_path(resource), notice: translate_with_resource('create.success'))
    else
      render :new,
             locals: { page: Administrate::Page::Form.new(dashboard, resource) },
             status: :unprocessable_entity
    end
  end

  def update
    if requested_resource.update(resource_params)
      redirect_to(
        after_resource_updated_path(requested_resource),
        notice: translate_with_resource('update.success')
      )
    else
      render :edit,
             locals: { page: Administrate::Page::Form.new(dashboard, requested_resource) },
             status: :unprocessable_entity
    end
  end

  def destroy
    requested_resource.soft_delete!
    redirect_to(
      after_resource_destroyed_path(requested_resource),
      notice: translate_with_resource('destroy.success')
    )
  end

  # Audit report: who viewed the notification, when, and from which IP.
  # One row per `OperationsNotificationAck`. Pre-loads the user + account
  # to keep the view straight-forward.
  def acks
    @notification = OperationsNotification.find(params[:id])
    @acks = @notification
            .operations_notification_acks
            .includes(:user, :account)
            .order(acknowledged_at: :desc)
  end

  private

  def scoped_resource
    OperationsNotification.where(deleted_at: nil)
  end

  # `account_ids` and `audience_user_ids` come in from the custom form
  # as repeated hidden inputs, which `params.require(...).permit(...)`
  # rejects unless declared as array values. Administrate's default
  # `permitted_attributes` only knows about scalar fields, so we widen
  # it here.
  def resource_params
    params.require(:operations_notification).permit(
      :title, :body, :severity, :scope_type, :audience_type,
      :trigger_kind, :expires_at,
      account_ids: [], audience_user_ids: []
    ).tap do |permitted|
      permitted[:account_ids] = Array(permitted[:account_ids]).reject(&:blank?).map(&:to_i)
      permitted[:audience_user_ids] = Array(permitted[:audience_user_ids]).reject(&:blank?).map(&:to_i)
      permitted[:expires_at] = parse_expires_at(permitted[:expires_at])
    end
  end

  # The form uses `<input type="datetime-local">`, which submits a naive
  # ISO string like `"2026-06-23T23:59"` with no timezone. Rails would
  # parse it against `Time.zone` (UTC by default in Chatwoot), so an
  # operator in São Paulo typing `23:59` ends up persisted as
  # `23:59 UTC` (= 20:59 -03) — three hours earlier than intended.
  # Re-interpret the string explicitly in `America/Sao_Paulo`, which is
  # the same zone the super-admin index/show already render in.
  def parse_expires_at(raw)
    return nil if raw.blank?
    return raw unless raw.is_a?(String)

    ActiveSupport::TimeZone[OperationsNotificationDashboard::LOCAL_TZ].parse(raw)
  end
end
