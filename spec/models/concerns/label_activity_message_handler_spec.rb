require 'rails_helper'

RSpec.describe LabelActivityMessageHandler do
  let(:account)      { create(:account) }
  let(:user)         { create(:user, account: account, name: 'John Smith') }
  let(:conversation) { create(:conversation, account: account) }

  before { Current.user = user }

  after { Current.user = nil }

  def expected_params(content)
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
  end

  it 'enqueues a label-change activity for regular labels' do
    expect { conversation.update!(label_list: ['cliente']) }
      .to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, expected_params('John Smith added cliente'))
  end

  it 'silences the label-change activity when only the agente-off label is added' do
    expect { conversation.update!(label_list: ['agente-off']) }
      .not_to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, hash_including(content: a_string_matching(/agente-off/)))
  end

  it 'silences the label-change activity when only the agente-off label is removed' do
    conversation.update!(label_list: ['agente-off'])

    expect { conversation.update!(label_list: []) }
      .not_to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, hash_including(content: a_string_matching(/agente-off/)))
  end

  it 'still enqueues for the visible labels when agente-off is added together with others' do
    expect { conversation.update!(label_list: %w[cliente agente-off]) }
      .to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, expected_params('John Smith added cliente'))
  end
end
