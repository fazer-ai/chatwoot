require 'rails_helper'

RSpec.describe AdditionalAttributesMerge do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, additional_attributes: { 'city' => 'Curitiba' }) }

  describe '#merge_additional_attributes!' do
    it 'merges against the row rather than against this object' do
      Contact.find(contact.id).update!(additional_attributes: { 'city' => 'Curitiba', 'company_name' => 'fazer.ai' })

      contact.merge_additional_attributes!(merge: { 'country' => 'Brazil' })

      expect(contact.reload.additional_attributes)
        .to eq('city' => 'Curitiba', 'company_name' => 'fazer.ai', 'country' => 'Brazil')
    end

    it 'leaves the receiver alone, because the lock is taken on a separate row object' do
      contact.merge_additional_attributes!(merge: { 'country' => 'Brazil' })

      expect(contact.additional_attributes).to eq('city' => 'Curitiba')
    end

    # A Conversation carries a dirty `display_id` from creation on purpose, so anything built on
    # `with_lock` would raise here instead of writing.
    it 'writes even when the record has unsaved changes' do
      conversation = create(:conversation, account: account)

      expect(conversation.changed).to include('display_id')
      expect { conversation.merge_additional_attributes!(merge: { 'conversation_language' => 'pt' }) }
        .not_to raise_error
      expect(conversation.reload.additional_attributes).to include('conversation_language' => 'pt')
    end

    it 'stringifies the keys it is handed, so one key cannot arrive under two spellings' do
      contact.merge_additional_attributes!(merge: { city: 'Sao Paulo' })

      stored = ActiveRecord::Base.connection.select_value(
        "SELECT additional_attributes::text FROM contacts WHERE id = #{contact.id}"
      )

      expect(stored.scan('city').size).to eq(1)
      expect(contact.reload.additional_attributes).to eq('city' => 'Sao Paulo')
    end

    it 'carries the other columns of the same write' do
      contact.merge_additional_attributes!(attributes: { name: 'Equipe' }, merge: { 'owner' => '1@lid' })

      expect(contact.reload).to have_attributes(name: 'Equipe')
      expect(contact.additional_attributes).to include('owner' => '1@lid')
    end

    # The write has to keep being a write: `before_save :sync_contact_attributes` is what copies
    # `city` into the `location` column, and `update_columns` would skip it in silence.
    it 'still runs the callbacks a write runs' do
      contact.merge_additional_attributes!(merge: { 'city' => 'Sao Paulo' })

      expect(contact.reload.location).to eq('Sao Paulo')
    end

    it 'does not touch the row when the merge changes nothing' do
      before_write = contact.reload.updated_at

      expect(contact.merge_additional_attributes!(merge: { 'city' => 'Curitiba' })).to be(false)
      expect(contact.reload.updated_at).to eq(before_write)
    end

    # Every caller is enrichment after a network round trip. Before this existed the write simply
    # matched zero rows and the job ended clean; raising would turn a deleted contact into a job
    # that retries until it gives up.
    it 'answers false when the row disappeared during the call' do
      id = contact.id
      Contact.find(id).destroy!

      expect(contact.merge_additional_attributes!(merge: { 'city' => 'Sao Paulo' })).to be(false)
    end

    describe 'writing inside a nested namespace' do
      it 'keeps the siblings already stored there' do
        contact.update!(additional_attributes: { 'external' => { 'hubspot_id' => 'hs_1' } })

        contact.merge_additional_attributes!(under: 'external', merge: { 'leadsquared_id' => 'ls_1' })

        expect(contact.reload.additional_attributes['external'])
          .to eq('hubspot_id' => 'hs_1', 'leadsquared_id' => 'ls_1')
      end

      it 'removes one key and leaves the rest of the namespace standing' do
        contact.update!(additional_attributes: { 'external' => { 'hubspot_id' => 'hs_1', 'leadsquared_id' => 'ls_1' } })

        contact.merge_additional_attributes!(under: 'external', remove: ['leadsquared_id'])

        expect(contact.reload.additional_attributes['external']).to eq('hubspot_id' => 'hs_1')
      end

      it 'does not seed an empty namespace for a removal that had nowhere to happen' do
        expect(contact.merge_additional_attributes!(under: 'external', remove: ['leadsquared_id'])).to be(false)
        expect(contact.reload.additional_attributes).to eq('city' => 'Curitiba')
      end

      # Whatever is stored under the key, if it is not a hash it is not a namespace, and writing
      # inside it means replacing it.
      it 'replaces a stored value that is not a hash' do
        contact.update!(additional_attributes: { 'external' => 'ls_1' })

        contact.merge_additional_attributes!(under: 'external', merge: { 'leadsquared_id' => 'ls_1' })

        expect(contact.reload.additional_attributes['external']).to eq('leadsquared_id' => 'ls_1')
      end
    end
  end
end
