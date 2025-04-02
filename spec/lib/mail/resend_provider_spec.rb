require 'rails_helper'

describe Mail::ResendProvider do
  let(:provider) { described_class.new({}) }
  let(:mail) do
    instance_double(Mail::Message,
                    smtp_envelope_from: 'sender@example.com',
                    smtp_envelope_to: ['receiver@example.com'],
                    subject: 'Test Email',
                    decoded: 'This is a test email message.')
  end

  describe '#deliver!' do
    it 'calls Resend with the correct parameters' do
      response = instance_double(HTTParty::Response, success?: true)
      allow(Resend::Emails).to receive(:send)
        .with(
          from: mail.smtp_envelope_from,
          to: mail.smtp_envelope_to,
          subject: mail.subject,
          html: mail.decoded
        )
        .and_return(response)

      provider.deliver!(mail)

      expect(Resend::Emails).to have_received(:send)
    end

    context 'when response is not successful' do
      it 'raises a DeliveryError with the error message' do
        allow(Resend::Emails).to receive(:send)
          .with(
            from: mail.smtp_envelope_from,
            to: mail.smtp_envelope_to,
            subject: mail.subject,
            html: mail.decoded
          )
          .and_raise(Resend::Error.new('Service unavailable'))

        expect { provider.deliver!(mail) }
          .to raise_error(described_class::DeliveryError, 'Failed to send email: Service unavailable')
      end
    end

    context 'when an exception occurs during sending' do
      it 'raises a DeliveryError with the exception message' do
        allow(Resend::Emails).to receive(:send).and_raise(StandardError, 'Connection timed out')

        expect { provider.deliver!(mail) }
          .to raise_error(described_class::DeliveryError, 'An error occurred while sending email: Connection timed out')
      end
    end
  end
end
