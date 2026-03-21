class InternalChat::PollService
  pattr_initialize [:poll!, :user!, :option!]

  def vote
    validate_option_belongs_to_poll!
    validate_vote!
    option.votes.create!(user: user)
    poll.reload
  end

  def unvote
    validate_option_belongs_to_poll!
    vote_record = option.votes.find_by!(user: user)
    vote_record.destroy!
    poll.reload
  end

  private

  def validate_option_belongs_to_poll!
    raise ArgumentError, 'Option does not belong to this poll' unless option.internal_chat_poll_id == poll.id
  end

  def validate_vote!
    raise StandardError, 'Poll has expired' if poll.expired?

    existing_votes = InternalChat::PollVote.joins(:option).where(
      internal_chat_poll_options: { internal_chat_poll_id: poll.id },
      user_id: user.id
    )

    return unless existing_votes.exists?
    raise StandardError, 'Revoting is not allowed' unless poll.allow_revote

    existing_votes.destroy_all unless poll.multiple_choice
  end
end
