require 'rails_helper'

RSpec.describe AiStatusActivityMessageHandler do
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

  describe 'attribute mode' do
    before { account.update!(ai_status_uses_attribute: true) }

    it 'enqueues an activity message when ai_enabled flips to false' do
      conversation.update!(ai_enabled: true)

      expect { conversation.update!(ai_enabled: false) }
        .to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, expected_params('John Smith turned the AI off'))
    end

    it 'enqueues an activity message when ai_enabled flips to true' do
      conversation.update!(ai_enabled: false)

      expect { conversation.update!(ai_enabled: true) }
        .to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, expected_params('John Smith turned the AI on'))
    end

    it 'does not enqueue when ai_enabled does not change' do
      conversation.update!(ai_enabled: false)

      expect { conversation.update!(updated_at: Time.zone.now) }
        .not_to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, hash_including(content: a_string_matching(/AI/)))
    end

    it 'falls back to the system wording when there is no current user' do
      Current.user = nil
      conversation.update!(ai_enabled: true)

      expect { conversation.update!(ai_enabled: false) }
        .to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, expected_params('AI turned off'))
    end
  end

  describe 'legacy label mode' do
    before { account.update!(ai_status_uses_attribute: false) }

    it 'enqueues an activity message when the agente-off label is added' do
      conversation.update!(label_list: ['cliente'])

      expect { conversation.update!(label_list: %w[cliente agente-off]) }
        .to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, expected_params('John Smith turned the AI off'))
    end

    it 'enqueues an activity message when the agente-off label is removed' do
      conversation.update!(label_list: %w[cliente agente-off])

      expect { conversation.update!(label_list: ['cliente']) }
        .to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, expected_params('John Smith turned the AI on'))
    end

    it 'does not enqueue an AI activity for unrelated label changes' do
      conversation.update!(label_list: ['cliente'])

      expect { conversation.update!(label_list: %w[cliente vip]) }
        .not_to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversation, hash_including(content: a_string_matching(/IA/)))
    end
  end
end
