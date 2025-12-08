# frozen_string_literal: true

class Api::V1::Accounts::Kanban::AccountUserPreferencesController < Api::V1::Accounts::Kanban::BaseController
  def update
    preference = Current.account_user.kanban_preference || Current.account_user.build_kanban_preference
    authorize(preference)

    preference.preferences.deep_merge!(preference_params)
    preference.save!

    head :no_content
  end

  private

  def preference_params
    params.require(:preferences).permit!
  end
end
