require 'rails_helper'

describe ContactDrop do
  subject(:contact_drop) { described_class.new(contact) }

  let!(:contact) { create(:contact, custom_attributes: { car_model: 'Tesla Model S', car_year: '2022' }) }

  context 'when first name' do
    it 'returns first name' do
      contact.update!(name: 'John Doe')
      expect(subject.first_name).to eq 'John'
    end

    it('return the capitalized name') do
      contact.update!(name: 'john doe')
      expect(subject.name).to eq 'John Doe'
    end

    it('return the capitalized first name') do
      contact.update!(name: 'john doe')
      expect(subject.last_name).to eq 'Doe'
    end

    it 'returns the single-word name as the first name (no fallback to nil)' do
      contact.update!(name: 'maria')
      expect(subject.first_name).to eq 'Maria'
    end
  end

  context 'when last name' do
    it 'returns the last name' do
      contact.update!(name: 'John Doe')
      expect(subject.last_name).to eq 'Doe'
    end

    it 'falls back to the single-word name so liquid tokens never render empty' do
      contact.update!(name: 'John')
      expect(subject.last_name).to eq 'John'
    end

    it('return the capitalized last name') do
      contact.update!(name: 'john doe')
      expect(subject.last_name).to eq 'Doe'
    end
  end

  context 'when accessing custom attributes' do
    it 'returns the correct car model from custom attributes' do
      expect(contact_drop.custom_attribute['car_model']).to eq 'Tesla Model S'
    end

    it 'returns the correct car year from custom attributes' do
      expect(contact_drop.custom_attribute['car_year']).to eq '2022'
    end

    it 'returns empty hash when there are no custom attributes' do
      contact.update!(custom_attributes: nil)
      expect(contact_drop.custom_attribute).to eq({})
    end

    it 'strips html tags out of string custom attribute values' do
      contact.update!(custom_attributes: { remark: '<script>alert(1)</script>important' })
      expect(contact_drop.custom_attribute['remark']).to eq 'important'
    end
  end

  context 'with html-bearing names (defense in depth)' do
    it 'strips script tags from name before rendering' do
      contact.update!(name: 'Maria <script>alert(1)</script>')
      expect(contact_drop.name).to eq 'Maria'
    end

    it 'strips inline event handlers in image tags' do
      contact.update!(name: '<img src=x onerror=alert(1)> Joao')
      expect(contact_drop.name).to eq 'Joao'
    end

    it 'preserves legitimate ampersands and unicode in names' do
      contact.update!(name: 'Mary & John 💚')
      expect(contact_drop.name).to eq 'Mary & John 💚'
    end

    it 'strips tags from email-shaped strings too' do
      contact.update!(email: '<b>bold</b>user@example.com')
      expect(contact_drop.email).to eq 'bolduser@example.com'
    end

    it 'derives first_name and last_name from the sanitized name' do
      contact.update!(name: '<script>x</script>Maria Silva')
      expect(contact_drop.first_name).to eq 'Maria'
      expect(contact_drop.last_name).to eq 'Silva'
    end
  end
end
