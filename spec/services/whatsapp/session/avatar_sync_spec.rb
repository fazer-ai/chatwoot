require 'rails_helper'

# The module had no spec of its own before #534, which mattered once its two writers moved onto
# the shared primitive: they were being changed without anything watching.
RSpec.describe Whatsapp::Session::AvatarSync do
  let(:contact) do
    create(:contact, additional_attributes: {
             'city' => 'Uberlandia',
             'last_avatar_sync_at' => 1.minute.ago.iso8601,
             'avatar_url_hash' => Digest::SHA256.hexdigest('https://example.com/old.png')
           })
  end

  # A fence, not a checklist. The defect in #534 was a read-modify-write on this one JSON column
  # persisting a copy taken before something slow, and it existed in four places at once. Assert
  # that nothing writes the column directly any more, so the next writer inherits the lock and
  # the re-read instead of the bug.
  it 'is the only shape in which the shared column is written' do
    roots = %w[app enterprise lib].select { |dir| Rails.root.join(dir).directory? }
    writers = Dir.glob(Rails.root.join("{#{roots.join(',')}}/**/*.rb")).select do |path|
      File.read(path).match?(/update_columns?\(\s*additional_attributes/)
    end

    expect(writers.map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s })
      .to contain_exactly('app/models/concerns/avatarable.rb')
  end

  describe '.reset' do
    it 'clears both markers and leaves everything else alone' do
      described_class.reset(contact)

      expect(contact.reload.additional_attributes).to eq('city' => 'Uberlandia')
    end

    it 'ignores a blank contact' do
      expect { described_class.reset(nil) }.not_to raise_error
    end

    # The markers are what a stale picture has to clear before it can be refetched, so a caller
    # that read the hash before a round trip must not put them back by writing its own copy.
    it 'does not restore a marker another writer cleared first' do
      stale = Contact.find(contact.id)
      contact.update_avatar_sync_markers!(remove: described_class::MARKERS)

      described_class.reset(stale)

      expect(contact.reload.additional_attributes).not_to include('avatar_url_hash')
    end
  end

  describe '.remove' do
    it 'drops the picture and records when' do
      contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png',
                            content_type: 'image/png')

      described_class.remove(contact)

      contact.reload
      expect(contact.avatar).not_to be_attached
      expect(contact.additional_attributes).to include(described_class::REMOVED_AT)
      expect(contact.additional_attributes).to include('city' => 'Uberlandia')
      expect(contact.additional_attributes.keys).not_to include(*described_class::MARKERS)
    end

    it 'records the removal even when nothing was attached' do
      described_class.remove(contact)

      expect(contact.reload.additional_attributes).to include(described_class::REMOVED_AT)
    end

    # `remove` purges the blob first, which is a round trip to storage. Anything written to the
    # column while that runs has to survive, or the removal marker lands on a stale hash and
    # takes the other writer's key with it.
    it 'keeps a key written while the blob was being purged' do
      contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png',
                            content_type: 'image/png')
      allow(contact.avatar).to receive(:purge) do
        other = Contact.find(contact.id)
        # Deliberately not the shared primitive: this stands in for a writer that does not use
        # it, which is the whole hazard under test.
        other.update_columns(additional_attributes: (other.additional_attributes || {}).merge('country' => 'BR')) # rubocop:disable Rails/SkipsModelValidations
      end

      described_class.remove(contact)

      expect(contact.reload.additional_attributes).to include('country' => 'BR', described_class::REMOVED_AT => anything)
    end
  end

  describe '.refetch' do
    it 'clears the markers and queues the download with the moment the url was resolved' do
      expect { described_class.refetch(contact, 'https://example.com/new.png') }
        .to have_enqueued_job(Avatar::AvatarFromUrlJob)
        .with(contact, 'https://example.com/new.png', resolved_at: anything)

      expect(contact.reload.additional_attributes.keys).not_to include(*described_class::MARKERS)
    end

    it 'does nothing without a url' do
      expect { described_class.refetch(contact, nil) }.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
    end
  end
end
