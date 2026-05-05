class SuperAdmin::Profile::MfaController < SuperAdmin::ApplicationController
  layout 'super_admin/application'

  before_action :ensure_mfa_feature_available
  before_action :set_mfa_service

  def show
    @backup_codes = session.delete(:super_admin_mfa_backup_codes)
    @secret = @mfa_service.two_factor_setup_pending? ? current_super_admin.otp_secret : nil
    @provisioning_uri = @mfa_service.two_factor_provisioning_uri
    @qr_svg = render_qr(@provisioning_uri) if @provisioning_uri.present?
  end

  def create
    redirect_to super_admin_profile_mfa_path, alert: I18n.t('errors.mfa.already_enabled') and return if @mfa_service.mfa_enabled?

    @mfa_service.enable_two_factor!
    redirect_to super_admin_profile_mfa_path
  end

  def verify
    return redirect_with_alert(I18n.t('errors.mfa.already_enabled')) if @mfa_service.mfa_enabled?
    return redirect_with_alert(I18n.t('errors.mfa.invalid_code')) unless authenticate_otp(params[:otp_code])

    backup_codes = @mfa_service.verify_and_activate!
    session[:super_admin_mfa_backup_codes] = backup_codes if backup_codes
    redirect_to super_admin_profile_mfa_path
  end

  def destroy
    return redirect_with_alert(I18n.t('errors.mfa.not_enabled')) unless @mfa_service.mfa_enabled?
    return redirect_with_alert(I18n.t('errors.mfa.invalid_credentials')) unless current_super_admin.valid_password?(params[:password])
    return redirect_with_alert(I18n.t('errors.mfa.invalid_code')) unless authenticate_otp(params[:otp_code])

    @mfa_service.disable_two_factor!
    redirect_to super_admin_profile_mfa_path
  end

  def backup_codes
    return redirect_with_alert(I18n.t('errors.mfa.not_enabled')) unless @mfa_service.mfa_enabled?
    return redirect_with_alert(I18n.t('errors.mfa.invalid_code')) unless authenticate_otp(params[:otp_code])

    session[:super_admin_mfa_backup_codes] = @mfa_service.generate_backup_codes!
    redirect_to super_admin_profile_mfa_path
  end

  private

  def set_mfa_service
    @mfa_service = Mfa::ManagementService.new(user: current_super_admin)
  end

  def ensure_mfa_feature_available
    return if Chatwoot.mfa_enabled?

    redirect_to super_admin_root_path, alert: I18n.t('errors.mfa.feature_unavailable')
  end

  def authenticate_otp(otp_code)
    Mfa::AuthenticationService.new(user: current_super_admin, otp_code: otp_code).authenticate
  end

  def redirect_with_alert(message)
    redirect_to super_admin_profile_mfa_path, alert: message
  end

  def render_qr(uri)
    RQRCode::QRCode.new(uri).as_svg(
      module_size: 5,
      use_path: true,
      svg_attributes: { class: 'mfa-qr' }
    ).html_safe # rubocop:disable Rails/OutputSafety
  end
end
