# Summarizes a conversation with the account's OpenAI integration key, on an agent's request,
# and saves the result as a private note in the conversation. Used both by the manual
# "summarize" action and by the automatic handoff summary when a conversation changes agent.
#
# Captain's SummaryService does a similar call, but it runs on Captain's installation key and
# credits and is stripped from CE images; this one only needs the OpenAI integration hook.
class Integrations::Openai::ConversationSummaryService
  MESSAGE_LIMIT = 50

  pattr_initialize [:conversation!, :user!]

  def self.summarizable?(conversation)
    conversation.messages.where(message_type: [:incoming, :outgoing], private: false).exists?
  end

  def perform
    # The integration can be turned off between the request and the job.
    return if openai_hook.blank?
    return unless self.class.summarizable?(conversation)

    summary = summarize
    return if summary.blank?

    Messages::MessageBuilder.new(user, conversation, note_params(summary)).perform
  end

  private

  def note_params(summary)
    {
      content: "**#{I18n.t('integrations.openai.summary_note_title', locale: conversation.account.locale)}**\n\n#{summary}",
      private: true,
      content_attributes: { ai_summary: true }
    }
  end

  def summarize
    response = client.chat(parameters: { model: Llm::Config::DEFAULT_MODEL, messages: prompt_messages })
    response.dig('choices', 0, 'message', 'content')
  end

  def prompt_messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: transcript }
    ]
  end

  def system_prompt
    prompt = Rails.root.join('lib/integrations/openai/openai_prompts/summary.liquid').read
    "#{prompt}\nReply in #{conversation.account.locale_english_name}."
  end

  def transcript
    conversation.messages
                .where(message_type: [:incoming, :outgoing], private: false)
                .reorder(id: :desc)
                .limit(MESSAGE_LIMIT)
                .filter_map { |message| transcript_entry(message) }
                .reverse
                .join("\n")
  end

  def transcript_entry(message)
    text = message.content_for_llm
    "#{message.incoming? ? 'Customer' : 'Agent'}: #{text}" if text.present?
  end

  def openai_hook
    @openai_hook ||= conversation.account.hooks.find_by(app_id: 'openai', status: 'enabled')
  end

  def client
    OpenAI::Client.new(
      access_token: openai_hook.settings['api_key'],
      uri_base: InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
    )
  end
end
