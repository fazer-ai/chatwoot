require 'rails_helper'

describe Import::Email::Classifier do
  let(:own) { 'sac@example.com' }
  let(:from_customer) do
    Mail.read_from_string("From: cliente@example.com\r\nTo: #{own}\r\nSubject: Assunto #12345\r\n" \
                          "Message-ID: <x@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\n\r\nCorpo")
  end
  let(:from_mailbox) do
    Mail.read_from_string("From: #{own}\r\nTo: cliente@example.com\r\nSubject: Re: Assunto #12345\r\n" \
                          "Message-ID: <y@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\n\r\nCorpo")
  end
  let(:customer_text) { 'Bom dia, gostaria de cancelar meu pedido feito na semana passada, obrigado.' }

  # The same sentence arrives spelled three ways on a mailbox this old, and the folding is
  # what makes one pattern match all of them.
  ['solicitação 123 foi recebida', 'solicita&ccedil;&atilde;o 123 foi recebida',
   'solicitac&#807;a&#771;o 123 foi recebida'].each do |spelling|
    it "recognises a receipt spelled #{spelling[0, 26]}" do
      classifier = described_class.new(mail: from_customer, text: "Mensagem automatica: sua #{spelling} e esta sendo analisada")
      expect(classifier.kind).to eq(:receipt)
    end
  end

  it 'survives text that lies about its encoding rather than dropping the message' do
    expect { described_class.fold("caf\xE9 sem acento valido") }.not_to raise_error
  end

  it 'reads ordinary mail from a person as customer' do
    expect(described_class.new(mail: from_customer, text: customer_text).kind).to eq(:customer)
  end

  it 'separates the shapes the ticketing system writes' do
    alert = described_class.new(mail: from_customer, text: 'Chegou um novo ticket 456 que nao foi atribuido para nenhum agente')
    relay = described_class.new(mail: from_customer, text: 'Por favor acesse o octadesk e verifique essa solicitacao')
    csat = described_class.new(mail: from_customer, text: 'Responda nossa pesquisa de satisfacao sobre o atendimento de hoje')
    expect([alert.kind, relay.kind, csat.kind]).to eq(%i[alert relay csat])
  end

  it 'reads a body with nothing in it as empty' do
    expect(described_class.new(mail: from_customer, text: 'ok').kind).to eq(:empty)
  end

  # Gmail's \All holds the Sent folder, so a fifth of a support mailbox is its own outgoing
  # mail. Read as customer it would invent a contact for the company's own address.
  it 'reads the mailbox own mail as sent' do
    expect(described_class.new(mail: from_mailbox, text: customer_text, own_address: own).kind).to eq(:sent)
  end

  it 'decides sent by the sender before the text, since a reply quotes the mail it answers' do
    classifier = described_class.new(mail: from_mailbox, own_address: own,
                                     text: 'Chegou um novo ticket 456 que nao foi atribuido para nenhum agente')
    expect(classifier.kind).to eq(:sent)
  end

  it 'reads mail from somebody else as customer even when told the mailbox address' do
    expect(described_class.new(mail: from_customer, text: customer_text, own_address: own).kind).to eq(:customer)
  end

  it 'never answers sent when the caller does not say what the mailbox is' do
    expect(described_class.new(mail: from_mailbox, text: customer_text).kind).to eq(:customer)
  end

  it 'reads the ticket number off the end of the subject' do
    expect(described_class.new(mail: from_customer, text: 'corpo').ticket).to eq('12345')
  end

  it 'falls back to the ticket number in the body' do
    plain = Mail.read_from_string("From: c@example.com\r\nTo: #{own}\r\nSubject: sem numero\r\n" \
                                  "Message-ID: <z@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: plain, text: 'sobre o ticket 987 que abri ontem').ticket).to eq('987')
  end
end
