module Mail # rubocop:disable Style/ClassAndModuleChildren
  class ResendProvider
    class DeliveryError < StandardError; end

    # Resend builds the MIME message itself, so the headers it would otherwise drop are passed
    # through: without them a reply does not thread under the customer's mail.
    THREADING_HEADERS = %w[Message-ID In-Reply-To References].freeze

    def initialize(_settings); end

    def deliver!(mail)
      Resend::Emails.send(payload(mail))
    rescue Resend::Error => e
      raise DeliveryError, "Failed to send email: #{e.message}"
    rescue StandardError => e
      raise DeliveryError, "An error occurred while sending email: #{e.message}"
    end

    private

    def payload(mail)
      {
        from: mail.header[:from].to_s,
        to: mail.header[:to].to_s,
        cc: mail[:cc]&.formatted,
        bcc: mail[:bcc]&.formatted,
        reply_to: mail[:reply_to]&.formatted,
        subject: mail.header[:subject].to_s,
        **bodies(mail),
        headers: threading_headers(mail).presence,
        attachments: mail.attachments.map { |attachment| attachment_payload(attachment) }.presence
      }.compact
    end

    # A message with an attachment is multipart, and `Mail::Message#decoded` raises on those.
    def bodies(mail)
      html = mail.multipart? ? mail.html_part&.decoded : mail.decoded
      { html: html, text: mail.text_part&.decoded || sanitize_html(html.to_s) }
    end

    def threading_headers(mail)
      THREADING_HEADERS.filter_map { |name| [name, mail.header[name].value] if mail.header[name] }.to_h
    end

    def attachment_payload(attachment)
      {
        filename: attachment.filename,
        content: Base64.strict_encode64(attachment.decoded),
        content_type: attachment.mime_type,
        content_id: (attachment.content_id.delete('<>') if attachment.inline?)
      }.compact
    end

    def sanitize_html(html)
      sanitized = ActionView::Base.full_sanitizer.sanitize(html)
      # NOTE: Remove more than two consecutive newlines
      sanitized.lines.map(&:strip).join("\n").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
