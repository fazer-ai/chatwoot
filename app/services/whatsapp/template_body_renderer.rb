class Whatsapp::TemplateBodyRenderer
  pattr_initialize [:channel!, :template_params!]

  def call
    return nil if template_params.blank?

    template = find_template
    return nil if template.blank?

    body = template_body(template)
    return nil if body.blank?

    substitute_placeholders(body, body_params)
  end

  private

  def find_template
    channel.message_templates.find do |t|
      t['name'] == template_params['name'] &&
        t['language']&.downcase == template_params['language']&.downcase &&
        t['status']&.downcase == 'approved'
    end
  end

  def template_body(template)
    body_component = template['components']&.find { |c| c['type']&.upcase == 'BODY' }
    body_component&.dig('text')
  end

  def body_params
    processed = template_params['processed_params'] || {}
    processed['body'].is_a?(Hash) ? processed['body'] : processed
  end

  def substitute_placeholders(body, params)
    body.gsub(/\{\{(\w+)\}\}/) do |match|
      key = Regexp.last_match(1)
      params[key].presence || params[key.to_sym].presence || match
    end
  end
end
