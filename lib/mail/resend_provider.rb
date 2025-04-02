module Mail # rubocop:disable Style/ClassAndModuleChildren
  class ResendProvider
    class DeliveryError < StandardError; end

    def deliver!(mail)
      Resend::Emails.send(
        from: mail.smtp_envelope_from,
        to: mail.smtp_envelope_to,
        subject: mail.subject,
        html: mail.decoded
      )
    rescue Resend::Error => e
      raise DeliveryError, "Failed to send email: #{e.message}"
    rescue StandardError => e
      raise DeliveryError, "An error occurred while sending email: #{e.message}"
    end
  end
end
