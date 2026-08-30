require 'rails_helper'

describe Import::Email::Download do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:pacer) { Import::Email::Pacer.new(budget_mb: Float::INFINITY, max_load: 99) }
  let(:stats) { Hash.new(0) }
  let(:leaf) do
    Struct.new(:media_type, :subtype, :encoding, :param, :disposition, :size, keyword_init: true) # rubocop:disable Lint/StructNewOverride
  end
  let(:structure) do
    Struct.new(:subtype, :parts, keyword_init: true) do
      def media_type = 'MULTIPART'
      def encoding = nil
      def param = nil
      def disposition = nil
      def size = 0
    end.new(subtype: 'MIXED',
            parts: [leaf.new(media_type: 'IMAGE', subtype: 'PNG', encoding: 'BASE64', param: {},
                             disposition: Struct.new(:dsp_type, :param).new('ATTACHMENT'), size: 3_000_000)])
  end
  let(:header) do
    "From: cliente@example.com\r\nTo: #{channel.email}\r\nSubject: fotos\r\n" \
      "Message-ID: <so-anexo@example.com>\r\nDate: #{Time.zone.parse('2023-05-01 10:00').rfc2822}\r\n"
  end
  let(:meta) do
    Struct.new(:attr).new({ 'BODY[HEADER]' => header, 'BODYSTRUCTURE' => structure, 'RFC822.SIZE' => 3_100_000 })
  end
  let(:imap) { instance_double(Net::IMAP) }

  before do
    allow(imap).to receive(:uid_fetch).with(10, ['BODY.PEEK[HEADER]', 'BODYSTRUCTURE', 'RFC822.SIZE']).and_return([meta])
  end

  def download(attachments)
    described_class.new(pacer: pacer, attachments: Import::Email::AttachmentPolicy.build(attachments), stats: stats)
  end

  # `BODY.PEEK[]` pulls the encoded attachments along with the words, which is the download
  # the cutoff exists to refuse. A message that is nothing but attachments has no text part
  # to name, and falling back to the whole message there fetches every file the policy just
  # excluded and then discards them -- on exactly the messages where the fallback is the
  # entire message.
  describe 'a message under the cutoff whose structure names no text part' do
    it 'builds it from the header rather than downloading what it will not keep' do
      expect(download(nil).perform(imap, 10)).to include('so-anexo@example.com')
      expect(imap).not_to have_received(:uid_fetch).with(10, 'BODY.PEEK[]')
    end

    it 'reports it as a row still owed its attachments' do
      run = download(nil)
      run.perform(imap, 10)
      expect(run).to be_lean
      expect(stats[:sem_anexos]).to eq(1)
    end
  end

  # Nothing to save on a message whose attachments the run is taking anyway: both fetches
  # cost the same bytes and one of them costs an extra round trip.
  it 'takes the whole message when the policy wants the attachments' do
    allow(imap).to receive(:uid_fetch).with(10, 'BODY.PEEK[]')
                                      .and_return([Struct.new(:attr).new({ 'BODY[]' => "#{header}\r\ncorpo" })])
    run = download(:all)

    expect(run.perform(imap, 10)).to include('corpo')
    expect(run).not_to be_lean
    expect(run).not_to be_declined
  end

  # The ceiling sits under a provider limit whose answer to an overdraft is locking IMAP
  # for the whole account, live fetch included. Noticing after the transfer is a ceiling
  # plus one message, and the message that crosses it is the one carrying the attachments.
  it 'refuses a message larger than what is left of the budget' do
    tight = Import::Email::Pacer.new(budget_mb: 1, max_load: 99)
    run = described_class.new(pacer: tight, attachments: Import::Email::AttachmentPolicy.build(:all), stats: stats)

    expect(run.perform(imap, 10)).to be_nil
    expect(run).to be_declined
    expect(imap).not_to have_received(:uid_fetch).with(10, 'BODY.PEEK[]')
  end
end
