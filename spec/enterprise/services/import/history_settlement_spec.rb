require 'rails_helper'

# The Enterprise half of the contact clock. `update_columns` skips the callback that rolls
# a contact's activity up to its company, which is deliberate everywhere else -- the import
# writes clocks without firing the machinery around them -- so the roll-up has to be asked
# for, and asked for from the tree where Company exists.
describe Enterprise::Import::HistorySettlement do # rubocop:disable RSpec/SpecFilePathFormat -- the subject is the OSS module this one is prepended into
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:company) { create(:company, account: account, domain: 'empresa.example.com') }
  let(:contact) { create(:contact, account: account, company: company) }
  let(:conversation) do
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  let(:settler) do
    Class.new do
      include Import::HistorySettlement
      attr_reader :opened

      def initialize = @opened = Set.new
      def announcing(&) = yield
      def run(rows) = settle(rows, [])
    end
  end

  def incoming(at)
    Import::SilentWrite.wrap do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, sender: contact, created_at: at,
                       content_attributes: { imported: true })
    end
  end

  it 'rolls the imported clock up to the company' do
    settler.new.run([incoming(Time.zone.parse('2023-05-01 10:00'))])
    expect(company.reload.last_activity_at).to eq(Time.zone.parse('2023-05-01 10:00'))
  end

  # A company somebody is talking to today keeps its clock; that is the company's own rule
  # and history has no business overriding it.
  it 'never drags a company backwards' do
    company.update!(last_activity_at: Time.zone.parse('2026-01-01 09:00'))
    settler.new.run([incoming(Time.zone.parse('2023-05-01 10:00'))])
    expect(company.reload.last_activity_at).to eq(Time.zone.parse('2026-01-01 09:00'))
  end

  it 'leaves a contact with no company alone rather than raising' do
    contact.update!(company: nil)
    expect { settler.new.run([incoming(Time.zone.parse('2023-05-01 10:00'))]) }.not_to raise_error
  end
end
