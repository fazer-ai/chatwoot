require 'rails_helper'

# The gap that let a whole round's fix ship as a no-op: the classifier was given a `reply:`
# and every spec passed one in by hand, so nothing ever asked the presenter for it.
describe Import::Email::Body do
  let(:account) { create(:account) }
  let(:customer) { 'Bom dia, gostaria de cancelar meu pedido feito na semana passada, obrigado.' }
  let(:receipt) { 'Mensagem automatica: sua solicitacao 123 foi recebida e esta sendo analisada' }

  def body_for(text: nil, html: nil)
    parts = if html
              "MIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"b\"\r\n\r\n" \
                "--b\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n#{text}\r\n" \
                "--b\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n#{html}\r\n--b--\r\n"
            else
              "Content-Type: text/plain; charset=UTF-8\r\n\r\n#{text}"
            end
    mail = Mail.read_from_string(
      "From: cliente@example.com\r\nTo: sac@example.com\r\nSubject: assunto\r\n" \
      "Message-ID: <b@example.com>\r\nDate: Mon, 1 May 2023 10:00:00 -0300\r\n#{parts}"
    )
    described_class.new(MailPresenter.new(mail, account))
  end

  describe 'a reply that quotes what it answers' do
    let(:body) { body_for(text: "#{customer}\n\nEm 1 de maio, sac@example.com escreveu:\n> #{receipt}") }

    it 'gives the whole message for :full' do
      expect(body[:full]).to include(customer).and include(receipt)
    end

    # `MailPresenter` files the trimmed body under `:quoted` and returns the untrimmed
    # message for `:reply`. Asking it for `:reply` gets the quote back and undoes the point.
    it 'gives only the words the sender typed for :reply' do
      expect(body[:reply]).to include(customer)
      expect(body[:reply]).not_to include(receipt)
    end
  end

  describe 'a message that carries only html' do
    let(:body) { body_for(text: '', html: "<p>#{customer}</p><blockquote>#{receipt}</blockquote>") }

    it 'falls back to the html with its tags stripped' do
      expect(body[:full]).to include(customer)
    end
  end

  it 'is empty for a message with no body at all rather than raising' do
    expect(body_for(text: '')[:reply]).to eq('')
  end

  it 'refuses a reading it does not define' do
    expect { body_for(text: customer)[:quoted] }.to raise_error(KeyError)
  end
end
