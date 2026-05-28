# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::PollVote do
  describe 'associations' do
    it { is_expected.to belong_to(:option).class_name('InternalChat::PollOption') }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { create(:internal_chat_poll_vote) }

    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:internal_chat_poll_option_id) }
  end
end
