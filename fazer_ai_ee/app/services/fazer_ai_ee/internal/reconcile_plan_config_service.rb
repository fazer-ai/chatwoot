# The branding keys the fork adds (fazer_ai_ee/config/premium_installation_config.yml) are
# reset with upstream's, since they reach the customer the same way the dashboard logo does.
module FazerAiEe::Internal::ReconcilePlanConfigService
  FORK_PREMIUM_CONFIG = YAML.safe_load_file(Rails.root.join('fazer_ai_ee/config/premium_installation_config.yml')).freeze

  private

  def premium_config
    (super + FORK_PREMIUM_CONFIG).freeze
  end
end
