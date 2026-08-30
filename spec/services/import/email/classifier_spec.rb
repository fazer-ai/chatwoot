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

  # The test is for a blank message rather than a short one, and it is taken over the
  # subject and the body together: `from_customer` carries a subject, so `ok` under it is a
  # customer answering a thread and not a message saying nothing.
  it 'reads a message with nothing on either line as empty' do
    blank = Mail.read_from_string("From: cliente@example.com\r\nTo: #{own}\r\nSubject: \r\n" \
                                  "Message-ID: <y@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\n\r\n")
    expect(described_class.new(mail: blank, text: '').kind).to eq(:empty)
  end

  it 'keeps a short answer under a subject of its own' do
    expect(described_class.new(mail: from_customer, text: 'ok').kind).to eq(:customer)
  end

  # Gmail's \All holds the Sent folder, so a fifth of a support mailbox is its own outgoing
  # mail. Read as customer it would invent a contact for the company's own address.
  it 'reads the mailbox own mail as sent' do
    expect(described_class.new(mail: from_mailbox, text: customer_text, own_addresses: own).kind).to eq(:sent)
  end

  it 'decides sent by the sender before the text, since a reply quotes the mail it answers' do
    classifier = described_class.new(mail: from_mailbox, own_addresses: own,
                                     text: 'Chegou um novo ticket 456 que nao foi atribuido para nenhum agente')
    expect(classifier.kind).to eq(:sent)
  end

  it 'reads mail from somebody else as customer even when told the mailbox address' do
    expect(described_class.new(mail: from_customer, text: customer_text, own_addresses: own).kind).to eq(:customer)
  end

  # A channel has two: the address the inbox publishes and the one it authenticates as.
  # They differ on legacy Google aliases and on Microsoft UPN setups, and it is the login
  # that owns the Sent copies -- read as customer they would be filed as things customers
  # wrote, on a fifth of the mailbox.
  it 'reads mail from the login as sent, even when it is not the published address' do
    alias_mail = Mail.read_from_string("From: sac.antigo@example.com\r\nTo: cliente@example.com\r\n" \
                                       "Subject: Re: assunto\r\nMessage-ID: <a@example.com>\r\n\r\nCorpo")
    classifier = described_class.new(mail: alias_mail, text: customer_text,
                                     own_addresses: [own, 'sac.antigo@example.com'])
    expect(classifier.kind).to eq(:sent)
  end

  # The website form posts as the company and points Reply-To at the customer, so `From` is
  # ours and the message is inbound. Read as sent it is refused outright and the cursor
  # moves past it -- every message the form ever generated, gone.
  it 'reads mail sent on somebody else behalf as customer, whatever the From says' do
    form = Mail.read_from_string("From: #{own}\r\nReply-To: cliente@example.com\r\nTo: #{own}\r\n" \
                                 "Subject: contato pelo site\r\nMessage-ID: <f@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: form, text: customer_text, own_addresses: own).kind).to eq(:customer)
  end

  # A Reply-To that is also ours is an ordinary outgoing mail carrying a routing header.
  it 'still reads our own reply as sent when the Reply-To is also ours' do
    routed = Mail.read_from_string("From: #{own}\r\nReply-To: #{own}\r\nTo: cliente@example.com\r\n" \
                                   "Subject: Re: assunto\r\nMessage-ID: <r@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: routed, text: customer_text, own_addresses: own).kind).to eq(:sent)
  end

  # A list or a forwarder puts our own address in `From` and the customer in
  # `X-Original-Sender`, with no `Reply-To` at all. `MailPresenter#original_sender` reads
  # that header ahead of `From`, so the importer would file the message as inbound from the
  # customer -- but only if the classifier lets it through, and read on `From` alone the
  # whole class answers `:sent`, which a run refuses outright.
  it 'reads X-Original-Sender the way the presenter does when there is no Reply-To' do
    forwarded = Mail.read_from_string("From: #{own}\r\nX-Original-Sender: Cliente <cliente@example.com>\r\n" \
                                      "To: #{own}\r\nSubject: pergunta\r\nMessage-ID: <x@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: forwarded, text: customer_text, own_addresses: own).kind).to eq(:customer)
  end

  # `Reply-To` comes first in that order, so it decides on its own and the other header is
  # not consulted -- the same precedence the presenter applies.
  it 'lets our own Reply-To settle it even when X-Original-Sender points elsewhere' do
    routed = Mail.read_from_string("From: #{own}\r\nReply-To: #{own}\r\nX-Original-Sender: cliente@example.com\r\n" \
                                   "To: cliente@example.com\r\nSubject: Re: assunto\r\nMessage-ID: <y@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: routed, text: customer_text, own_addresses: own).kind).to eq(:sent)
  end

  it 'reads our own outgoing mail as sent when it carries neither header' do
    plain = Mail.read_from_string("From: #{own}\r\nTo: cliente@example.com\r\n" \
                                  "Subject: Re: assunto\r\nMessage-ID: <z@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: plain, text: customer_text, own_addresses: own).kind).to eq(:sent)
  end

  # A form that lists its own routing address beside the customer is still delegating, and
  # one owned address in the list would be enough to have the message refused.
  it 'reads a mixed Reply-To as delegated rather than as our own' do
    mixed = Mail.read_from_string("From: #{own}\r\nReply-To: #{own}, cliente@example.com\r\n" \
                                  "To: #{own}\r\nSubject: contato\r\nMessage-ID: <m@example.com>\r\n\r\nCorpo")
    expect(described_class.new(mail: mixed, text: customer_text, own_addresses: own).kind).to eq(:customer)
  end

  it 'ignores a blank second address rather than matching everything' do
    expect(described_class.new(mail: from_customer, text: customer_text, own_addresses: [own, nil]).kind)
      .to eq(:customer)
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

  # A customer answering machine mail quotes it. Read whole, the body carries the
  # template's phrases and the reply is filed as the machine mail it answers -- which under
  # the default `KINDS=customer` drops the customer's words and moves the cursor past them.
  describe 'a customer answering machine mail' do
    let(:quoted_receipt) do
      "#{customer_text}\n\nEm 1 de maio, sac@example.com escreveu:\n" \
        '> Mensagem automatica: sua solicitacao 123 foi recebida e esta sendo analisada por nossa equipe'
    end

    it 'is the customer, not the receipt underneath the reply' do
      classifier = described_class.new(mail: from_customer, text: quoted_receipt, reply: customer_text)
      expect(classifier.kind).to eq(:customer)
    end

    it 'still reads the ticket number out of the part that was quoted' do
      body = "#{customer_text}\n\n> sobre o ticket 987 que abri ontem"
      plain = Mail.read_from_string("From: c@example.com\r\nTo: #{own}\r\nSubject: sem numero\r\n" \
                                    "Message-ID: <w@example.com>\r\n\r\nCorpo")
      expect(described_class.new(mail: plain, text: body, reply: customer_text).ticket).to eq('987')
    end

    # A receipt's own fixed text is the unquoted top of it, so trimming changes nothing.
    it 'leaves the machine mail itself classified as before' do
      receipt = 'Mensagem automatica: sua solicitacao 123 foi recebida'
      classifier = described_class.new(mail: from_customer, text: "#{receipt}\n\n> #{customer_text}", reply: receipt)
      expect(classifier.kind).to eq(:receipt)
    end

    it 'falls back to the whole body when nothing survives the trim' do
      receipt = 'Mensagem automatica: sua solicitacao 123 foi recebida'
      expect(described_class.new(mail: from_customer, text: receipt, reply: '').kind).to eq(:receipt)
    end
  end

  # A support mailbox is written from phones, and a phone puts the whole request on the
  # subject line and leaves the body to its own signature. Judged on the body alone the
  # message reads as empty, `skip?` drops it, and the cursor moves past a customer's
  # question with no error anywhere.
  describe 'a request that lives on the subject line' do
    def kind_of(subject, body)
      mail = Mail.new(from: 'cliente@example.com', to: 'sac@example.com', subject: subject, body: body)
      described_class.new(mail: mail, text: body, own_addresses: ['sac@example.com']).kind
    end

    it 'reads the subject as part of what the message says' do
      expect(kind_of('Como faco para entrar com pessoas menores de idade', 'Enviado do meu iPhone')).to eq(:customer)
    end

    it 'still calls a message with nothing on either line empty' do
      expect(kind_of('Re:', '')).to eq(:empty)
    end

    # The side to err on, and it is a choice rather than an oversight: a signature with no
    # subject over it comes in as a thin row. An archive pays for that once. It pays for a
    # dropped request forever, and silently, because `skip?` moves the cursor past it.
    it 'lets a bare signature through rather than risk the request beside it' do
      expect(kind_of('', 'Enviado do meu iPhone')).to eq(:customer)
    end

    # `Re: Fwd:` is nine characters that would rescue a message saying nothing.
    it 'does not count the reply prefixes as content' do
      expect(kind_of('Re: Fwd: Enc: ok', '')).to eq(:empty)
    end

    # Every kind above the emptiness test is decided by who sent the message or by a
    # template's fixed phrases, and both live in the body.
    it 'leaves a message the sender already settled alone' do
      mail = Mail.new(from: 'sac@example.com', to: 'cliente@example.com', subject: 'Uma pergunta bem comprida do cliente', body: '')
      expect(described_class.new(mail: mail, text: '', own_addresses: ['sac@example.com']).kind).to eq(:sent)
    end
  end
end
