class ApplicationMailer < ActionMailer::Base
  include ActionView::Helpers::SanitizeHelper

  EMAIL_SAFE_LOGO_FORMATS = %w[.png .jpg .jpeg .gif].freeze

  default from: ENV.fetch('MAILER_SENDER_EMAIL', 'Chatwoot <accounts@chatwoot.com>')
  around_action :with_isolated_current
  around_action :switch_locale
  layout 'mailer/base'
  # Fetch template from Database if available
  # Order: Account Specific > Installation Specific > Fallback to file
  prepend_view_path ::EmailTemplate.resolver
  append_view_path Rails.root.join('app/views/mailers')
  helper :frontend_urls
  helper do
    def global_config
      @global_config ||= GlobalConfig.get('BRAND_NAME', 'BRAND_URL')
    end
  end

  rescue_from(*ExceptionList::SMTP_EXCEPTIONS, with: :handle_smtp_exceptions)

  def liquid_filters
    [LiquidFilters::I18nFilter]
  end

  def smtp_config_set_or_development?
    ENV.fetch('SMTP_ADDRESS', nil).present? || ENV.fetch('RESEND_API_KEY', nil).present? || Rails.env.development?
  end

  private

  def handle_smtp_exceptions(message)
    Rails.logger.warn 'Failed to send Email'
    Rails.logger.error "Exception: #{message}"
  end

  def send_mail_with_liquid(*args)
    Rails.logger.info "Email sent to #{args[0][:to]} with subject #{args[0][:subject]}"
    mail(*args) do |format|
      # explored sending a multipart email containing both text type and html
      # parsing the html with nokogiri will remove the links as well
      # might also remove tags like b,li etc. so lets rethink about this later
      # format.text { Nokogiri::HTML(render(layout: false)).text }
      format.html { render }
    end
  end

  def liquid_droppables
    # Merge additional objects into this in your mailer
    # liquid template handler converts these objects into drop objects
    {
      account: Current.account,
      user: @agent,
      conversation: @conversation,
      inbox: @conversation&.inbox
    }
  end

  def liquid_locals
    # expose variables you want to be exposed in liquid
    config = GlobalConfig.get('BRAND_NAME', 'BRAND_URL', 'BRAND_COLOR', 'LOGO_EMAIL', 'LOGO')
    locals = {
      global_config: config,
      # Two roles, because one hex cannot serve both: see BrandColor.
      brand_color: BrandColor.surface(config['BRAND_COLOR']),
      brand_color_text: BrandColor.on_light(config['BRAND_COLOR']),
      brand_logo_url: absolute_asset_url(email_logo(config)),
      action_url: @action_url
    }

    locals.merge({ attachment_url: @attachment_url }) if @attachment_url
    locals.merge({ failed_contacts: @failed_contacts, imported_contacts: @imported_contacts })
    locals
  end

  # Falling back to LOGO covers the installation that already has a raster logo without asking
  # it to configure a second one. It is guarded on the extension because LOGO is an SVG by
  # default, and email clients render none: an unconditional fallback would put a broken image
  # in every email, which reads worse than the no-logo layout it replaced.
  def email_logo(config)
    return config['LOGO_EMAIL'] if config['LOGO_EMAIL'].present?

    logo = config['LOGO'].to_s
    logo if EMAIL_SAFE_LOGO_FORMATS.any? { |format| logo.split('?').first.to_s.downcase.end_with?(format) }
  end

  # LOGO_EMAIL is configured the way LOGO is, as a path served by this installation, but an
  # email is read outside it and a relative src resolves against nothing.
  def absolute_asset_url(path)
    value = path.to_s.strip
    return value if value.blank? || value.start_with?('http://', 'https://')

    "#{ENV.fetch('FRONTEND_URL', nil)}#{value}"
  end

  def locale_from_account(account)
    return unless account

    I18n.available_locales.map(&:to_s).include?(account.locale) ? account.locale : nil
  end

  # Current is thread-local and nothing downstream resets it, so a mailer that left the
  # account set would hand it to whatever ran next on the same thread -- the rest of an
  # automation rule inline, or the next Sidekiq job on that worker thread.
  def with_isolated_current
    Current.isolate do
      account = params.try(:[], :account)
      Current.account = account if account.present?
      yield
    end
  end

  def switch_locale(&)
    locale ||= locale_from_account(Current.account)
    locale ||= I18n.default_locale
    # ensure locale won't bleed into other requests
    # https://guides.rubyonrails.org/i18n.html#managing-the-locale-across-requests
    I18n.with_locale(locale, &)
  end
end
