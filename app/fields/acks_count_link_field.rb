require 'administrate/field/base'

# Renders the count of acknowledgements on a notification as a link to
# the audit report (super_admin acks page). Lives alongside the simpler
# `CountField`; only used by `OperationsNotificationDashboard`.
class AcksCountLinkField < Administrate::Field::Base
  def count
    data.count
  end

  def notification_id
    resource.id
  end
end
