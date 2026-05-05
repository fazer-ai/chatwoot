class SuperAdmin::Sessions::MfaChallengeController < ApplicationController
  layout false

  before_action :load_pending_super_admin
  before_action :ensure_mfa_feature_available

  def show; end

  def create
    if authenticate_otp(params[:otp_code]) || authenticate_backup_code(params[:backup_code])
      session.delete(:super_admin_pending_mfa_id)
      sign_in(:super_admin, @pending_super_admin)
      flash.discard
      redirect_to super_admin_users_path
    else
      flash.now[:error] = I18n.t('errors.mfa.invalid_code')
      render :show, status: :unauthorized
    end
  end

  private

  def load_pending_super_admin
    pending_id = session[:super_admin_pending_mfa_id]
    @pending_super_admin = SuperAdmin.find_by(id: pending_id)
    return if @pending_super_admin&.mfa_enabled?

    session.delete(:super_admin_pending_mfa_id)
    redirect_to new_super_admin_session_path
  end

  def ensure_mfa_feature_available
    return if Chatwoot.mfa_enabled?

    session.delete(:super_admin_pending_mfa_id)
    redirect_to new_super_admin_session_path
  end

  def authenticate_otp(otp_code)
    return false if otp_code.blank?

    Mfa::AuthenticationService.new(user: @pending_super_admin, otp_code: otp_code).authenticate
  end

  def authenticate_backup_code(backup_code)
    return false if backup_code.blank?

    Mfa::AuthenticationService.new(user: @pending_super_admin, backup_code: backup_code).authenticate
  end
end
