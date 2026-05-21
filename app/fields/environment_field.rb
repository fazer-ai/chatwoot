require 'administrate/field/base'

# `environment` toggle on Super Admin → Accounts. Behaves like a normal
# Administrate Field::Select dropdown but ships an inline JS guard that
# pops a `confirm()` when the admin tries to move an account from `test`
# to `production`. Going the other way (production → test) is silent
# because it's a less-disruptive transition.
class EnvironmentField < Administrate::Field::Select
  def to_s
    data.to_s
  end
end
