require 'rails_helper'

describe Import::Octadesk::TicketImporter do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:importer) { described_class.new(inbox: inbox) }
  let(:opened_at) { '2023-05-10T12:00:00Z' }

  let(:ticket) do
    {
      'Number' => 4321, 'RequesterMail' => 'cliente@example.com', 'RequesterName' => 'Cliente Um',
      'DateCreation' => { '$date' => opened_at }, 'DoneDate' => { '$date' => '2023-05-11T09:00:00Z' },
      'Interactions' => [
        { '_id' => { '$binary' => { 'base64' => 'AAAAAAAAAAAAAAAA' } },
          'Comments' => [{ 'Content' => 'Bom dia, preciso cancelar meu pedido.' }],
          'Person' => { 'Type' => 0, 'Name' => 'Cliente Um' },
          'DateCreation' => { '$date' => opened_at } },
        { '_id' => { '$binary' => { 'base64' => 'AAAAAAAAAAAAAAAB' } },
          'Comments' => [{ 'Content' => 'Boa tarde, ja cancelamos para voce.' }],
          'Person' => { 'Type' => 1, 'Name' => 'Atendente Dois' },
          'DateCreation' => { '$date' => '2023-05-10T15:00:00Z' } }
      ]
    }
  end

  it 'files the ticket as one resolved conversation dated to when it opened' do
    importer.import(ticket)
    conversation = inbox.conversations.last
    expect(conversation.status).to eq('resolved')
    expect(conversation.created_at).to eq(Time.zone.parse(opened_at))
    expect(conversation.status_changed_at).to eq(Time.zone.parse('2023-05-11T09:00:00Z'))
  end

  it 'reads direction off the export rather than guessing it from headers' do
    importer.import(ticket)
    expect(inbox.messages.reorder(:created_at).pluck(:message_type)).to eq(%w[incoming outgoing])
  end

  # An outgoing message with no sender and no sender_name renders as the bot, which would
  # attribute every agent reply in the archive to one.
  it 'names the agent who wrote an outgoing message' do
    importer.import(ticket)
    outgoing = inbox.messages.find_by(message_type: :outgoing)
    expect(outgoing.additional_attributes['sender_name']).to eq('Atendente Dois')
  end

  it 'keys the conversation on an indexed column so the lookup does not scan the inbox' do
    importer.import(ticket)
    expect(inbox.conversations.last.identifier).to eq('octadesk:4321')
    expect(inbox.conversations.last.custom_attributes['octadesk']).to eq('4321')
  end

  it 'writes nothing twice when the ticket comes round again' do
    importer.import(ticket)
    expect { described_class.new(inbox: inbox).import(ticket) }.not_to change(inbox.messages, :count)
  end

  describe 'a ticket whose whole history is status changes' do
    let(:activity_only) do
      ticket.merge(
        'Number' => 4322,
        'Interactions' => [
          { '_id' => { '$binary' => { 'base64' => 'AAAAAAAAAAAAAAAC' } }, 'Comments' => [],
            'PropertiesChanges' => { 'Status' => 'Resolvido' },
            'Person' => { 'Type' => 1, 'Name' => 'Atendente Dois' },
            'DateCreation' => { '$date' => '2023-05-10T13:00:00Z' } }
        ]
      )
    end

    it 'is still history and still becomes a conversation' do
      importer.import(activity_only)
      conversation = inbox.conversations.find_by(identifier: 'octadesk:4322')
      expect(conversation).to be_present
      expect(conversation.messages.pluck(:message_type)).to eq(['activity'])
      expect(conversation.messages.first.content).to eq('Status: Resolvido (por Atendente Dois)')
    end

    it 'is empty only when nothing at all would be written' do
      importer.import(ticket.merge('Number' => 4323, 'Interactions' => []))
      expect(inbox.conversations.find_by(identifier: 'octadesk:4323')).to be_nil
      expect(importer.stats[:sem_conteudo]).to eq(1)
    end

    # "Gatilho executado: notificar o solicitante" is machinery, not an event.
    it 'is empty when the only interactions are triggers' do
      trigger = activity_only['Interactions'].first.merge('Person' => { 'Type' => 3 })
      importer.import(activity_only.merge('Number' => 4324, 'Interactions' => [trigger]))
      expect(inbox.conversations.find_by(identifier: 'octadesk:4324')).to be_nil
    end
  end

  describe 'resuming a run that stopped between the write and the settlement' do
    it 'repairs stamps the next pass would otherwise never touch, because it writes nothing' do
      importer.import(ticket)
      conversation = inbox.conversations.last
      settled = conversation.last_activity_at
      conversation.update_columns(last_activity_at: Time.current, waiting_since: Time.current) # rubocop:disable Rails/SkipsModelValidations -- the state an interrupted run leaves behind

      described_class.new(inbox: inbox).import(ticket)
      expect(conversation.reload.last_activity_at).to eq(settled)
      expect(conversation.waiting_since).to be_nil
    end

    it 'backdates a conversation created before its first message was written' do
      importer.import(ticket)
      conversation = inbox.conversations.last
      conversation.messages.destroy_all
      conversation.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- ditto

      described_class.new(inbox: inbox).import(ticket)
      expect(conversation.reload.last_activity_at).to eq(conversation.messages.maximum(:created_at))
    end

    # A run that stops between the insert and the metadata leaves a thread with no labels and
    # a resolution stamped at the moment of the import, and the next pass finds it, returns
    # it and writes nothing.
    it 'reapplies the labels a stopped run never got to' do
      tagged = ticket.merge('Number' => 4331, 'Tags' => [{ 'Name' => 'cancelamento' }, 'urgente'])
      importer.import(tagged)
      conversation = inbox.conversations.find_by(identifier: 'octadesk:4331')
      conversation.update!(label_list: [])

      described_class.new(inbox: inbox).import(tagged)
      expect(conversation.reload.label_list).to contain_exactly('cancelamento', 'urgente')
    end

    it 'restamps a resolution a stopped run never got to' do
      importer.import(ticket)
      conversation = inbox.conversations.last
      conversation.update_columns(status_changed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- the state an interrupted run leaves

      described_class.new(inbox: inbox).import(ticket)
      expect(conversation.reload.status_changed_at).to eq(Time.zone.parse('2023-05-11T09:00:00Z'))
    end

    # A pass over an archive that is already right should cost a read and no label writes:
    # reapplying every label on every resume is a write per ticket over the whole export.
    it 'does not rewrite the labels that are already there' do
      tagged = ticket.merge('Number' => 4332, 'Tags' => [{ 'Name' => 'cancelamento' }])
      importer.import(tagged)
      conversation = inbox.conversations.find_by(identifier: 'octadesk:4332')

      writes = 0
      subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        writes += 1 if payload[:sql].start_with?('INSERT', 'UPDATE') && payload[:sql].include?('taggings')
      end
      described_class.new(inbox: inbox).import(tagged)
      ActiveSupport::Notifications.unsubscribe(subscription)
      expect(conversation.reload.label_list).to eq(['cancelamento'])
      expect(writes).to eq(0)
    end

    # The third interruption point, and the one a "did I write anything" test gets wrong:
    # the comments landed and the activity rows did not. The next pass writes a batch that
    # is real but partial, and settling from it alone drags the thread back to whichever
    # row happened to be missing.
    it 'settles from the whole thread when the pass only wrote the rows that were missing' do
      partial = ticket.merge(
        'Number' => 4326,
        'Interactions' => ticket['Interactions'] + [
          { '_id' => { '$binary' => { 'base64' => 'AAAAAAAAAAAAAAAD' } }, 'Comments' => [],
            'PropertiesChanges' => { 'Status' => 'Resolvido' },
            'Person' => { 'Type' => 1, 'Name' => 'Atendente Dois' },
            'DateCreation' => { '$date' => '2023-05-10T13:00:00Z' } }
        ]
      )
      importer.import(partial)
      conversation = inbox.conversations.find_by(identifier: 'octadesk:4326')
      newest = conversation.messages.maximum(:created_at)
      conversation.messages.where(message_type: :activity).destroy_all
      conversation.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- ditto

      described_class.new(inbox: inbox).import(partial)
      expect(conversation.reload.last_activity_at).to eq(newest)
    end
  end

  # The vendor's bucket stops existing when the subscription does, so an attachment a run
  # failed to fetch has to still be owed on the next pass. Which means the test for "already
  # stored" has to be exact.
  describe 'attachments a pass could not finish' do
    let(:with_attachments) do
      ticket.merge(
        'Number' => 4327,
        'Interactions' => [ticket['Interactions'].first.merge(
          'Attachments' => [
            { 'Url' => 'https://storage.googleapis.com/tenant/a/foto.png', 'Name' => 'foto.png' },
            { 'Url' => 'https://storage.googleapis.com/tenant/b/foto.png', 'Name' => 'foto.png' }
          ]
        )]
      )
    end

    before do
      stub_request(:get, 'https://storage.googleapis.com/tenant/a/foto.png')
        .to_return(status: 200, body: 'primeiro', headers: { 'content-type' => 'image/png' })
    end

    # Two different files under one name is ordinary: a customer sends a photo, an agent
    # sends another, and the vendor names both after the camera. Keyed on the filename, the
    # one that got through calls the one that did not done, and it is never fetched again.
    it 'still owes the copy that failed, even under a name that is already stored' do
      stub_request(:get, 'https://storage.googleapis.com/tenant/b/foto.png').to_return(status: 500)
      described_class.new(inbox: inbox, attachments: true).import(with_attachments)
      message = inbox.messages.find_by(message_type: :incoming)
      expect(message.attachments.count).to eq(1)

      stub_request(:get, 'https://storage.googleapis.com/tenant/b/foto.png')
        .to_return(status: 200, body: 'segundo', headers: { 'content-type' => 'image/png' })
      described_class.new(inbox: inbox, attachments: true).import(with_attachments)
      expect(message.reload.attachments.count).to eq(2)
    end

    # An interaction listing the same URL twice is the vendor's business, not ours. Read
    # only from the snapshot taken before the loop, the second copy is another download of a
    # file just stored -- on a run whose cost is the downloads.
    it 'fetches a url listed twice in the same interaction once' do
      repeated = ticket.merge(
        'Number' => 4328,
        'Interactions' => [ticket['Interactions'].first.merge(
          'Attachments' => Array.new(2) { { 'Url' => 'https://storage.googleapis.com/tenant/a/foto.png', 'Name' => 'foto.png' } }
        )]
      )
      described_class.new(inbox: inbox, attachments: true).import(repeated)
      expect(inbox.messages.find_by(message_type: :incoming).attachments.count).to eq(1)
      expect(a_request(:get, 'https://storage.googleapis.com/tenant/a/foto.png')).to have_been_made.once
    end

    it 'does not fetch one twice when both are already stored' do
      stub_request(:get, 'https://storage.googleapis.com/tenant/b/foto.png')
        .to_return(status: 200, body: 'segundo', headers: { 'content-type' => 'image/png' })
      described_class.new(inbox: inbox, attachments: true).import(with_attachments)
      described_class.new(inbox: inbox, attachments: true).import(with_attachments)
      expect(inbox.messages.find_by(message_type: :incoming).attachments.count).to eq(2)
    end
  end

  # A reply that is only a photo is an ordinary thing for a customer to send. Read as "no
  # comment" the interaction is a status change at best and nothing at all at worst, and it
  # takes the attachment with it -- to a bucket that stops existing when the subscription
  # does, which makes that loss permanent rather than late.
  describe 'an interaction that is only an attachment' do
    let(:only_a_file) do
      ticket.merge('Number' => 4330,
                   'Interactions' => [ticket['Interactions'].first.merge(
                     'Comments' => [], 'Attachments' => [{ 'Url' => 'https://storage.googleapis.com/t/a/foto.png', 'Name' => 'foto.png' }]
                   )])
    end

    before do
      stub_request(:get, 'https://storage.googleapis.com/t/a/foto.png')
        .to_return(status: 200, body: 'foto', headers: { 'content-type' => 'image/png' })
    end

    it 'files it as a message rather than dropping the whole interaction' do
      described_class.new(inbox: inbox, attachments: true).import(only_a_file)
      message = inbox.messages.find_by(message_type: :incoming)
      expect(message).to be_present
      expect(message.attachments.count).to eq(1)
    end

    # The row carries the sender, the date and its place in the thread whether or not this
    # pass is fetching files, and the pass that does finds it by interaction id.
    it 'files the row even on a pass that is not fetching attachments' do
      described_class.new(inbox: inbox).import(only_a_file)
      expect(inbox.messages.where(message_type: :incoming).count).to eq(1)

      described_class.new(inbox: inbox, attachments: true).import(only_a_file)
      expect(inbox.messages.find_by(message_type: :incoming).attachments.count).to eq(1)
    end

    it 'does not also write it as an activity line' do
      described_class.new(inbox: inbox).import(
        only_a_file.merge('Interactions' => [only_a_file['Interactions'].first.merge('PropertiesChanges' => { 'Status' => 'Resolvido' })])
      )
      expect(inbox.messages.where(message_type: :activity).count).to eq(0)
    end
  end

  # `Message` refuses more than fifteen and the mail pipeline trims to that before it
  # attaches anything. Past the sixteenth the bytes are spent on a download that produces a
  # message the dashboard will not render.
  it 'stops at the attachment cap rather than downloading past it' do
    urls = Array.new(18) { |i| "https://storage.googleapis.com/t/#{i}/f.png" }
    urls.each do |url|
      stub_request(:get, url).to_return(status: 200, body: url, headers: { 'content-type' => 'image/png' })
    end
    many = ticket.merge('Number' => 4331,
                        'Interactions' => [ticket['Interactions'].first.merge(
                          'Attachments' => urls.map { |url| { 'Url' => url, 'Name' => 'f.png' } }
                        )])

    run = described_class.new(inbox: inbox, attachments: true)
    run.import(many)
    expect(inbox.messages.find_by(message_type: :incoming).attachments.count).to eq(Message::NUMBER_OF_PERMITTED_ATTACHMENTS)
    expect(run.stats[:anexos_acima_do_teto]).to eq(3)
    expect(a_request(:get, urls.last)).not_to have_been_made
  end

  # A blank entry or a URL listed twice among the first fifteen would spend a slot, and the
  # real file at position sixteen is then never attempted -- not on this pass and not on any
  # later one, because every pass reads the same list the same way. The message ends up
  # holding fewer than the permitted number and still missing a file.
  it 'spends the cap on candidates rather than on blanks and repeats' do
    real = Array.new(15) { |i| "https://storage.googleapis.com/t/#{i}/f.png" }
    real.each { |url| stub_request(:get, url).to_return(status: 200, body: url, headers: { 'content-type' => 'image/png' }) }
    listed = [{ 'Url' => '', 'Name' => 'vazio' },
              { 'Url' => real.first, 'Name' => 'f.png' }] + real.map { |url| { 'Url' => url, 'Name' => 'f.png' } }
    mixed = ticket.merge('Number' => 4332,
                         'Interactions' => [ticket['Interactions'].first.merge('Attachments' => listed)])

    run = described_class.new(inbox: inbox, attachments: true)
    run.import(mixed)
    expect(inbox.messages.find_by(message_type: :incoming).attachments.count).to eq(15)
    expect(run.stats[:anexos_acima_do_teto]).to eq(0)
    expect(a_request(:get, real.last)).to have_been_made.once
  end

  # Like the mail importer, this one batches its own reindexes, so the per-row callback has
  # to be off while it writes or every row is indexed twice. The guard reads this flag
  # rather than the level.
  it 'takes the search index on itself while it writes' do
    seen = nil
    importer = described_class.new(inbox: inbox)
    allow(importer).to receive(:settle_ticket).and_wrap_original do |original, *args|
      seen = Import::SilentWrite.indexing?
      original.call(*args)
    end
    importer.import(ticket)
    expect(seen).to be(true)
  end

  # `Message` validates content at 150,000 and the mail path never reaches it, because
  # `MailboxSanitizer` truncates first. Left whole here, `create!` raises and the ticket is
  # abandoned where it stands: the interactions before it stay committed, so every retry
  # files nothing new, hits the same comment and gives up again.
  describe 'a comment longer than a message may be' do
    let(:enormous) do
      ticket.merge('Number' => 4329,
                   'Interactions' => [ticket['Interactions'].first.merge('Comments' => [{ 'Content' => 'a' * 160_000 }]),
                                      ticket['Interactions'].last])
    end

    it 'files it truncated rather than losing the rest of the ticket' do
      expect { described_class.new(inbox: inbox).import(enormous) }.not_to raise_error
      expect(inbox.messages.where(message_type: :incoming).first.content.length).to eq(150_000)
    end

    it 'still files the interactions after it' do
      described_class.new(inbox: inbox).import(enormous)
      expect(inbox.messages.where(message_type: :outgoing).count).to eq(1)
    end
  end

  describe 'the website form, which posts as the company' do
    let(:form_ticket) do
      ticket.merge(
        'Number' => 4325, 'RequesterMail' => 'contato@empresa.example.com', 'RequesterName' => 'Empresa',
        'Interactions' => [ticket['Interactions'].first.merge(
          'Comments' => [{ 'Content' => "Nome: Maria Souza\nEmail: maria@example.com\nMensagem: quero cancelar" }]
        )]
      )
    end

    it 'takes the customer out of the body when the ticket names the company' do
      described_class.new(inbox: inbox, form_address: 'contato@empresa.example.com',
                          form_sender_name: 'Empresa').import(form_ticket)
      contact = inbox.conversations.find_by(identifier: 'octadesk:4325').contact
      expect(contact.email).to eq('maria@example.com')
      expect(contact.name).to eq('Maria Souza')
    end

    it 'takes the ticket at its word when the caller says nothing about a form' do
      importer.import(form_ticket)
      expect(inbox.conversations.find_by(identifier: 'octadesk:4325').contact.email).to eq('contato@empresa.example.com')
    end

    # An `Email:` line in a comment is as likely to be somebody the customer is writing
    # about -- a colleague, a supplier, the address on an invoice -- as the customer.
    # Filing the thread under that person is worse than filing it under nobody.
    it 'does not take an address out of the body when no form is configured' do
      orphan = form_ticket.merge('Number' => 4328, 'RequesterMail' => nil)
      importer.import(orphan)
      expect(inbox.conversations.find_by(identifier: 'octadesk:4328')).to be_nil
      expect(importer.stats[:sem_contato]).to eq(1)
    end

    it 'takes it when the caller did configure a form' do
      orphan = form_ticket.merge('Number' => 4329, 'RequesterMail' => nil)
      described_class.new(inbox: inbox, form_address: 'contato@empresa.example.com').import(orphan)
      expect(inbox.conversations.find_by(identifier: 'octadesk:4329').contact.email).to eq('maria@example.com')
    end

    # Either configured value identifies the form on its own. Keyed on the address alone, a
    # deployment that knows only the display name takes the company address at face value
    # and merges every form ticket into one contact.
    it 'recognises the form by the name it posts under, with no address configured' do
      named = form_ticket.merge('Number' => 4330, 'RequesterName' => 'Formulario do Site')
      described_class.new(inbox: inbox, form_sender_name: 'Formulario do Site').import(named)
      expect(inbox.conversations.find_by(identifier: 'octadesk:4330').contact.email).to eq('maria@example.com')
    end
  end
end
