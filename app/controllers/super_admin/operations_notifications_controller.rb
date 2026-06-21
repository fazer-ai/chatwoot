class SuperAdmin::OperationsNotificationsController < SuperAdmin::ApplicationController
  # Notifications are *soft-deleted* (deleted_at) so the report keeps showing
  # historical acks even after the operator removes the entry from the active
  # list. The default scope is "active only" but the `deleted` filter on the
  # dashboard lets the operator browse the archived ones.

  def create
    resource = new_resource(resource_params.merge(created_by: current_user, published_at: Time.current))
    resource_saved = resource.save

    if resource_saved
      redirect_to(
        after_resource_created_path(resource),
        notice: translate_with_resource('create.success')
      )
    else
      render :new, locals: { page: Administrate::Page::Form.new(dashboard, resource) }, status: :unprocessable_entity
    end
  end

  def destroy
    requested_resource.soft_delete!
    redirect_to(
      after_resource_destroyed_path(requested_resource),
      notice: translate_with_resource('destroy.success')
    )
  end

  private

  def scoped_resource
    OperationsNotification.where(deleted_at: nil)
  end
end
