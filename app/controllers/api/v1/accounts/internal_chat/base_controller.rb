class Api::V1::Accounts::InternalChat::BaseController < Api::V1::Accounts::BaseController
  private

  def current_channel
    @current_channel ||= Current.account.internal_chat_channels.find(params[:channel_id] || params[:id])
  end

  def current_membership
    @current_membership ||= current_channel.channel_members.find_by(user_id: Current.user.id)
  end

  def channel_member?
    current_channel.channel_type_public_channel? || current_membership.present?
  end
end
