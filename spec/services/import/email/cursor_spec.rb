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

  it 'leaves the rest of the provider config alone' do
    channel.update!(provider_config: { 'keep' => 'me' })
    cursor.advance(folder, 5, 10)
    cursor.flush
    expect(channel.reload.provider_config['keep']).to eq('me')
  end
end
