require 'rails_helper'

# What the inbox cannot answer: how far a pass looked, as opposed to what it wrote. Most
# of a support mailbox is read and declined, and without this every pass re-downloads the
# declined mail, pays the same bytes and stops in the same place.
describe Import::Email::Cursor do
  let(:channel) { create(:channel_email) }
  let(:cursor) { described_class.new(channel) }
  let(:folder) { '[Gmail]/Todos os e-mails' }

  it 'takes every uid before anything has been marked' do
    expect(cursor.unseen(folder, 5, [1, 2, 3])).to eq([1, 2, 3])
  end

  it 'takes only what is above the mark once a pass has saved one' do
    cursor.advance(folder, 5, 2)
    cursor.flush
    expect(described_class.new(channel.reload).unseen(folder, 5, [1, 2, 3, 4])).to eq([3, 4])
  end

  it 'keeps a mark per folder, since spam is walked separately' do
    cursor.advance(folder, 5, 10)
    cursor.advance('[Gmail]/Spam', 7, 3)
    cursor.flush
    resumed = described_class.new(channel.reload)
    expect(resumed.unseen(folder, 5, [9, 10, 11])).to eq([11])
    expect(resumed.unseen('[Gmail]/Spam', 7, [3, 4])).to eq([4])
  end

  # A provider that renumbers a folder invalidates its own cursor. Trusting it would skip
  # into the middle of a folder whose uids now mean something else.
  it 'starts the folder over when the provider has renumbered it' do
    cursor.advance(folder, 5, 100)
    cursor.flush
    expect(described_class.new(channel.reload).unseen(folder, 6, [1, 2, 3])).to eq([1, 2, 3])
  end

  it 'never moves backwards, so a batch that stopped early cannot undo an earlier pass' do
    cursor.advance(folder, 5, 10)
    cursor.advance(folder, 5, 4)
    cursor.flush
    expect(described_class.new(channel.reload).unseen(folder, 5, [5, 10, 11])).to eq([11])
  end

  it 'writes nothing until it is flushed, so a run pays one update per batch' do
    cursor.advance(folder, 5, 10)
    expect(described_class.new(channel.reload).unseen(folder, 5, [1, 2])).to eq([1, 2])
  end

  it 'forgets everything when asked, so an operator can walk the mailbox again' do
    cursor.advance(folder, 5, 10)
    cursor.flush
    described_class.new(channel.reload).reset
    expect(described_class.new(channel.reload).unseen(folder, 5, [1, 2])).to eq([1, 2])
  end

  # The OAuth refresh services replace `provider_config` wholesale on every token renewal,
  # and an access token expires long before a multi-day import finishes. A cursor kept
  # there is deleted mid-run, and the run starts the mailbox over.
  it 'survives an OAuth token refresh, which replaces the provider config wholesale' do
    cursor.advance(folder, 5, 10)
    cursor.flush
    channel.update!(provider_config: { access_token: 'novo', refresh_token: 'novo', expires_on: 1.hour.from_now.to_s })
    expect(described_class.new(channel.reload).unseen(folder, 5, [9, 10, 11])).to eq([11])
  end

  it 'does not write over the credentials while saving its own mark' do
    channel.update!(provider_config: { access_token: 'guardado' })
    cursor.advance(folder, 5, 10)
    cursor.flush
    expect(channel.reload.provider_config['access_token']).to eq('guardado')
  end

  # UIDs rise with arrival, so widening the window asks for LOWER uids -- every one of them
  # below the mark a narrower pass left behind. Honoured, that mark reports the folder
  # exhausted while the older mail is still sitting there unread.
  describe 'when the selection changes' do
    let(:cursor) { described_class.new(channel, selection: [%w[SINCE 01-Jan-2024], [:customer]]) }

    it 'starts the folder over when the search widens to older mail' do
      cursor.advance(folder, 5, 100)
      cursor.flush
      widened = described_class.new(channel.reload, selection: [['ALL'], [:customer]])
      expect(widened.unseen(folder, 5, [10, 20, 30])).to eq([10, 20, 30])
    end

    it 'starts the folder over when the kinds widen, since declined mail was walked past' do
      cursor.advance(folder, 5, 100)
      cursor.flush
      widened = described_class.new(channel.reload, selection: [%w[SINCE 01-Jan-2024], [:customer, :receipt]])
      expect(widened.unseen(folder, 5, [10, 20, 30])).to eq([10, 20, 30])
    end

    # The policy changes nothing about which messages are imported and everything about
    # which are finished. Left out of the key, the mark from the narrow pass filters out
    # every uid before the enrichment path is ever asked about them.
    it 'starts the folder over when the attachment policy widens' do
      cursor.advance(folder, 5, 100)
      cursor.flush
      widened = described_class.new(channel.reload, selection: [%w[SINCE 01-Jan-2024], [:customer], 'all'])
      expect(widened.unseen(folder, 5, [10, 20, 30])).to eq([10, 20, 30])
    end

    it 'resumes when the same selection comes back, whatever order the kinds arrived in' do
      cursor.advance(folder, 5, 100)
      cursor.flush
      same = described_class.new(channel.reload, selection: [%w[SINCE 01-Jan-2024], [:customer]])
      expect(same.unseen(folder, 5, [99, 100, 101])).to eq([101])
    end
  end
end
