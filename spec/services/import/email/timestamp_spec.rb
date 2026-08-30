require 'rails_helper'

describe Import::Email::Timestamp do
  def mail_with(headers)
    Mail.read_from_string(
      "From: a@example.com\r\nTo: b@example.com\r\nMessage-ID: <x@example.com>\r\n#{headers}\r\nCorpo"
    )
  end

  it 'reads the Date header when it parses' do
    mail = mail_with("Date: Mon, 1 May 2023 10:00:00 -0300\r\n")
    expect(described_class.of(mail)).to eq(Time.zone.parse('2023-05-01 13:00:00 UTC'))
  end

  it 'falls back to the oldest Received line when there is no Date' do
    mail = mail_with("Received: from a by b; Tue, 14 Mar 2023 10:22:31 -0300\r\n")
    expect(described_class.of(mail)).to eq(Time.zone.parse('2023-03-14 13:22:31 UTC'))
  end

  it 'falls back when Date is text rather than a date' do
    mail = mail_with("Received: from a by b; Tue, 14 Mar 2023 10:22:31 -0300\r\nDate: nao e uma data\r\n")
    expect(described_class.of(mail)).to eq(Time.zone.parse('2023-03-14 13:22:31 UTC'))
  end

  it 'falls back when Date parses into an impossible time, which raises from the reader' do
    mail = mail_with("Received: from a by b; Tue, 14 Mar 2023 10:22:31 -0300\r\nDate: 32 Xxx 2023 99:99:99\r\n")
    expect(described_class.of(mail)).to eq(Time.zone.parse('2023-03-14 13:22:31 UTC'))
  end

  it 'answers nil when the mail says nothing usable, rather than answering now' do
    expect(described_class.of(mail_with(''))).to be_nil
  end
end
