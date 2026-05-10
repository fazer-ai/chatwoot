require 'rails_helper'

describe UserDrop do
  subject(:user_drop) { described_class.new(user) }

  let!(:user) { create(:user) }

  context 'when first name' do
    it 'returns first name' do
      user.update!(name: 'John Doe')
      expect(subject.first_name).to eq 'John'
    end

    it('return the capitalized first name') do
      user.update!(name: 'john doe')
      expect(subject.first_name).to eq 'John'
    end

    it 'returns the single-word name (no fallback to nil)' do
      user.update!(name: 'maria')
      expect(subject.first_name).to eq 'Maria'
    end
  end

  it('return the capitalized name') do
    user.update!(name: 'peter')
    expect(subject.name).to eq 'Peter'
  end

  context 'when last name' do
    it 'returns the last name' do
      user.update!(name: 'John Doe')
      expect(subject.last_name).to eq 'Doe'
    end

    it 'falls back to the single-word name so tokens never render empty' do
      user.update!(name: 'John')
      expect(subject.last_name).to eq 'John'
    end

    it('return the capitalized last name') do
      user.update!(name: 'john doe')
      expect(subject.last_name).to eq 'Doe'
    end
  end

  context 'with html-bearing names (defense in depth)' do
    it 'strips script tags from name before rendering' do
      user.update!(name: 'Maria <script>alert(1)</script>')
      expect(subject.name).to eq 'Maria'
    end

    it 'preserves legitimate ampersands' do
      user.update!(name: 'Mary & John')
      expect(subject.name).to eq 'Mary & John'
    end

    it 'strips html from email when somehow stored that way' do
      # Devise's email validator wouldn't allow the bad value through normal save.
      # update_columns bypasses validations to simulate corrupted data — defense
      # in depth: even if a row somehow has tags, the drop renders clean text.
      user.update_columns(email: '<b>bold</b>agent@example.com') # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.new(user.reload).email).to eq 'boldagent@example.com'
    end
  end
end
