class SuperAdmin::AccountsController < SuperAdmin::ApplicationController
  # Overwrite any of the RESTful controller actions to implement custom behavior
  # For example, you may want to send an email after a foo is updated.
  #
  # def update
  #   super
  #   send_foo_updated_email(requested_resource)
  # end

  # Override this method to specify custom lookup behavior.
  # This will be used to set the resource for the `show`, `edit`, and `update`
  # actions.
  #
  # def find_resource(param)
  #   Foo.find_by!(slug: param)
  # end

  # The result of this lookup will be available as `requested_resource`

  # Override this if you have certain roles that require a subset
  # this will be used to set the records shown on the `index` action.
  #
  # def scoped_resource
  #   if current_user.super_admin?
  #     resource_class
  #   else
  #     resource_class.with_less_stuff
  #   end
  # end

  # Override `resource_params` if you want to transform the submitted
  # data before it's persisted. For example, the following would turn all
  # empty values into nil values. It uses other APIs such as `resource_class`
  # and `dashboard`:
  #
  def resource_params
    permitted_params = super
    permitted_params[:limits] = permitted_params[:limits].to_h.compact
    permitted_params[:selected_feature_flags] = params[:enabled_features].keys.map(&:to_sym) if params[:enabled_features].present?
    merge_auris_settings(permitted_params)
    merge_auris_menus(permitted_params)
    permitted_params
  end

  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information

  def seed
    Internal::SeedAccountJob.perform_later(requested_resource)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account seeding triggered')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def reset_cache
    requested_resource.reset_cache_keys
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Cache keys cleared')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  # Prod accounts don't get the `env_test` auto-provisioning of the
  # Simulador inbox, but QA / demo runs on them still benefit from one.
  # `ensure_simulator_inbox!` is idempotent — a second click on an account
  # that already has a live simulator inbox is a no-op.
  def provision_simulator_inbox
    account = requested_resource
    already_had = account.simulator_inbox_id.present? && Inbox.exists?(id: account.simulator_inbox_id)
    account.ensure_simulator_inbox!
    notice = already_had ? 'Simulador inbox already exists — no action taken.' : 'Simulador inbox provisioned.'
    redirect_back(fallback_location: [namespace, account], notice: notice)
  end

  def destroy
    account = Account.find(params[:id])

    DeleteObjectJob.perform_later(account) if account.present?
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_back(fallback_location: [namespace, requested_resource], notice: 'Account deletion is in progress.')
    # rubocop:enable Rails/I18nLocaleTexts
  end

  private

  # Maps the "Auris settings" grid checkboxes (rendered by
  # AurisAccountSettingsField) onto the three boolean columns on the
  # `accounts` table that back them.
  def merge_auris_settings(permitted_params)
    return if params[:auris_settings].blank?

    auris = params.require(:auris_settings).permit(:funnel_enabled, :ai_status_uses_attribute, :multi_language_ai)
    permitted_params[:funnel_enabled] = auris[:funnel_enabled] == '1'
    permitted_params[:ai_status_uses_attribute] = auris[:ai_status_uses_attribute] == '1'
    permitted_params[:multi_language_ai] = auris[:multi_language_ai] == '1'
  end

  # Maps the "Auris menus" grid checkboxes (rendered by AurisAccountMenusField)
  # onto the two sidebar-visibility columns. Kept separate from the settings
  # writer so menu access stays an isolated concern: it doesn't ride along on
  # webhooks and a future Super Admin reshuffle can move it independently.
  def merge_auris_menus(permitted_params)
    return if params[:auris_menus].blank?

    menus = params.require(:auris_menus).permit(:inbox_view_menu_enabled, :help_center_menu_enabled)
    permitted_params[:inbox_view_menu_enabled] = menus[:inbox_view_menu_enabled] == '1'
    permitted_params[:help_center_menu_enabled] = menus[:help_center_menu_enabled] == '1'
  end
end

SuperAdmin::AccountsController.prepend_mod_with('SuperAdmin::AccountsController')
