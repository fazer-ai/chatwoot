# Renders Liquid tokens inside a WhatsApp campaign's template_params for a given
# contact. Returns a deep-cloned hash with every text-bearing field rendered
# against the same drops the message editor exposes (contact, agent, inbox,
# account). All other structure (template name, language, button types, media
# URLs that don't contain tokens) is preserved as-is so the WhatsApp Cloud API
# request stays valid.
class Whatsapp::CampaignTemplateLiquidRenderer
  pattr_initialize [:campaign!, :contact!, :template_params!]

  def call
    return template_params if template_params.blank?

    rendered = template_params.deep_dup
    rendered['processed_params'] = rendered_processed_params if processed_params.present?
    rendered
  end

  private

  def processed_params
    template_params['processed_params'] || {}
  end

  def rendered_processed_params
    rendered = processed_params.deep_dup
    rendered['body'] = render_section(rendered['body']) if rendered['body'].present?
    rendered['header'] = render_section(rendered['header']) if rendered['header'].present?
    rendered['buttons'] = render_buttons(rendered['buttons']) if rendered['buttons'].present?
    rendered
  end

  def render_section(section)
    case section
    when Hash then section.transform_values { |v| render_value(v) }
    when Array then section.map { |v| render_value(v) }
    else section
    end
  end

  def render_buttons(buttons)
    Array(buttons).map do |button|
      case button
      when Hash then button.merge('parameter' => render_value(button['parameter']))
      else button
      end
    end
  end

  def render_value(value)
    return value unless value.is_a?(String) && value.include?('{{')

    Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(value)
  end
end
