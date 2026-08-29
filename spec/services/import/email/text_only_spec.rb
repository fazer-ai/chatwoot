require 'rails_helper'

describe Import::Email::TextOnly do
  # Doubles rather than a live connection: what matters is the shape Net::IMAP returns for
  # BODYSTRUCTURE, and these carry the same readers the walk uses.
  # `size` is the reader Net::IMAP uses for a part's octets, so the double has to carry it.
  let(:leaf) do
    Struct.new(:media_type, :subtype, :encoding, :param, :disposition, :size, keyword_init: true) # rubocop:disable Lint/StructNewOverride
  end
  let(:multi) do
    Struct.new(:subtype, :parts, keyword_init: true) do
      def media_type = 'MULTIPART'
      def encoding = nil
      def param = nil
      def disposition = nil
      def size = 0
    end
  end
  let(:disposition) { Struct.new(:dsp_type, :param) }

  def text(subtype = 'PLAIN', size: 900, dsp: nil)
    leaf.new(media_type: 'TEXT', subtype: subtype, encoding: '7BIT',
             param: { 'CHARSET' => 'UTF-8' }, disposition: dsp, size: size)
  end

  def binary
    leaf.new(media_type: 'IMAGE', subtype: 'PNG', encoding: 'BASE64',
             param: {}, disposition: disposition.new('ATTACHMENT'), size: 3_000_000)
  end

  describe '#attachments?' do
    it 'is false for a message that is only text, where a second fetch would save nothing' do
      expect(described_class.new(text)).not_to be_attachments
      expect(described_class.new(multi.new(subtype: 'ALTERNATIVE', parts: [text, text('HTML')]))).not_to be_attachments
    end

    it 'is true when a part is not text' do
      expect(described_class.new(multi.new(subtype: 'MIXED', parts: [text, binary]))).to be_attachments
    end

    it 'counts text offered as a file, which weighs the same as any other attachment' do
      csv = text('CSV', size: 9000, dsp: disposition.new('ATTACHMENT'))
      expect(described_class.new(multi.new(subtype: 'MIXED', parts: [text, csv]))).to be_attachments
    end

    # Legacy mail names a file without ever saying `attachment`. Read on the disposition
    # alone the message looks free of attachments, so the whole of it is downloaded --
    # which is the byte the cutoff exists to refuse.
    it 'counts a text part named by its content type, with no disposition at all' do
      csv = leaf.new(media_type: 'TEXT', subtype: 'CSV', encoding: '7BIT',
                     param: { 'CHARSET' => 'UTF-8', 'NAME' => 'nota.csv' }, disposition: nil, size: 900_000)
      expect(described_class.new(multi.new(subtype: 'MIXED', parts: [text, csv]))).to be_attachments
    end

    it 'counts a text part offered inline under a filename' do
      csv = text('CSV', size: 900_000, dsp: disposition.new('INLINE', { 'FILENAME' => 'nota.csv' }))
      expect(described_class.new(multi.new(subtype: 'MIXED', parts: [text, csv]))).to be_attachments
    end

    it 'leaves an ordinary inline body alone' do
      body = text(dsp: disposition.new('INLINE', {}))
      expect(described_class.new(multi.new(subtype: 'ALTERNATIVE', parts: [body, text('HTML')]))).not_to be_attachments
    end
  end

  describe '#part' do
    it 'numbers a single-part body as section 1' do
      expect(described_class.new(text).part).to include(section: '1', type: 'text/plain')
    end

    it 'addresses a nested part the way BODY[n.m] does' do
      inner = multi.new(subtype: 'ALTERNATIVE', parts: [text, text('HTML', size: 3000)])
      structure = multi.new(subtype: 'MIXED', parts: [inner, binary])
      expect(described_class.new(structure).part[:section]).to eq('1.1')
    end

    it 'prefers plain when it says anything' do
      structure = multi.new(subtype: 'MIXED', parts: [text(size: 900), text('HTML', size: 9000), binary])
      expect(described_class.new(structure).part).to include(section: '1', type: 'text/plain')
    end

    # An HTML-only message still carries a plain alternative, and it is routinely an empty
    # stub. Preferring plain by subtype alone files those messages with no body at all.
    it 'passes over an empty plain stub for the HTML that carries the words' do
      structure = multi.new(subtype: 'MIXED', parts: [text(size: 2), text('HTML', size: 4000), binary])
      expect(described_class.new(structure).part).to include(section: '2', type: 'text/html')
    end

    # The floor decides the preference and nothing else: applied to the result it would
    # send "See attached" back to the whole message, attachment included.
    it 'takes a very short body rather than giving up on the message' do
      structure = multi.new(subtype: 'MIXED', parts: [text(size: 12), binary])
      expect(described_class.new(structure).part).to include(section: '1')
    end

    it 'is nil when the structure names no text at all, so the caller takes the whole message' do
      expect(described_class.new(multi.new(subtype: 'MIXED', parts: [binary, binary])).part).to be_nil
    end
  end

  describe '#rebuild' do
    let(:header) do
      "Return-Path: <a@example.com>\r\nFrom: A <a@example.com>\r\nTo: b@example.com\r\n" \
        "Subject: Assunto\r\nMessage-ID: <keep-me@example.com>\r\nReferences: <parent@example.com>\r\n" \
        "Date: Mon, 1 May 2023 10:00:00 -0300\r\nMIME-Version: 1.0\r\n" \
        "Content-Type: multipart/mixed; boundary=\"xyz\"\r\nContent-Transfer-Encoding: 7bit\r\n"
    end
    let(:rebuilt) do
      lean = described_class.new(multi.new(subtype: 'MIXED', parts: [text, binary]))
      Mail.read_from_string(lean.rebuild(header, 'Corpo de teste'))
    end

    it 'keeps the identity and threading headers the dedupe and the thread lookup read' do
      expect(rebuilt.message_id).to eq('keep-me@example.com')
      expect(rebuilt.references).to eq('parent@example.com')
      expect(rebuilt.subject).to eq('Assunto')
      expect(rebuilt.date).to eq(DateTime.parse('Mon, 1 May 2023 10:00:00 -0300'))
    end

    it 'announces the part that is standing in for the body, so the mail parses as single-part' do
      expect(rebuilt).not_to be_multipart
      expect(rebuilt.content_type).to eq('text/plain; charset=UTF-8')
      expect(rebuilt.body.decoded.strip).to eq('Corpo de teste')
    end

    it 'drops the multipart boundary it is no longer describing' do
      expect(rebuilt.header.to_s).not_to include('boundary')
    end
  end
end
