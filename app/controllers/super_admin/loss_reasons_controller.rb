class SuperAdmin::LossReasonsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.ordered
  end
end
