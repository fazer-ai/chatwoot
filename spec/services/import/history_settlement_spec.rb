require 'rails_helper'

# The shared settlement, exercised through a stand-in includer rather than through one of
# the importers: what is worth pinning is the rule, and each importer hands it the same
# thing -- a conversation and the rows written into it.
describe Import::HistorySettlement do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:group) { create(:contact, account: account, name: 'Grupo') }
  let(:conversation) do
    contact_inbox = create(:contact_inbox, contact: group, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: group, contact_inbox: contact_inbox)
  end

  let(:settler) do
    Class.new do
      include Import::HistorySettlement
      attr_reader :opened

      def initialize = @opened = Set.new
      def announcing(&) = yield
      def run(rows) = settle(rows, [])
      def run_contacts(conversation, rows) = stamp_contact(conversation, rows)
    end
  end

  # Written the way an importer writes, because the live `update_contact_activity` would
  # otherwise stamp every sender with `DateTime.now` and hide whatever the settlement did.
  def incoming(sender, at)
    Import::SilentWrite.wrap do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, sender: sender, created_at: at,
                       content_attributes: { imported: true })
    end
  end

  # On a group the conversation's contact is the group and each row was written by a
  # participant. Stamping the conversation's contact gives the group a clock it never
  # earned and leaves every participant at null.
  describe 'when the conversation is a group and the rows are its participants' do
    let(:ana) { create(:contact, account: account, name: 'Ana') }
    let(:bruno) { create(:contact, account: account, name: 'Bruno') }

    it 'stamps each participant from what that participant wrote' do
      rows = [incoming(ana, Time.zone.parse('2023-05-01 10:00')),
              incoming(bruno, Time.zone.parse('2023-06-10 09:00')),
              incoming(ana, Time.zone.parse('2023-03-01 08:00'))]
      settler.new.run(rows)
      expect(ana.reload.last_activity_at).to eq(Time.zone.parse('2023-05-01 10:00'))
      expect(bruno.reload.last_activity_at).to eq(Time.zone.parse('2023-06-10 09:00'))
    end

    it 'leaves the group itself alone, since the group never wrote anything' do
      settler.new.run([incoming(ana, Time.zone.parse('2023-05-01 10:00'))])
      expect(group.reload.last_activity_at).to be_nil
    end
  end

  it 'never drags a contact backwards, whoever wrote the row' do
    ana = create(:contact, account: account, last_activity_at: Time.zone.parse('2026-01-01 09:00'))
    settler.new.run([incoming(ana, Time.zone.parse('2023-05-01 10:00'))])
    expect(ana.reload.last_activity_at).to eq(Time.zone.parse('2026-01-01 09:00'))
  end

  # The resume path reads the thread back off the database, where `sender` on every row is
  # a query. Read off `sender_id` the batch costs one.
  it 'asks for the contacts once for the whole batch' do
    rows = Array.new(6) { |i| incoming(create(:contact, account: account), Time.zone.parse('2023-05-01 10:00') + i.days) }
    reloaded = conversation.messages.reload.to_a
    queries = 0
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      queries += 1 if payload[:sql].start_with?('SELECT') && payload[:sql].include?('"contacts"')
    end
    settler.new.run_contacts(conversation, reloaded)
    ActiveSupport::Notifications.unsubscribe(subscription)
    expect(rows.length).to eq(6)
    expect(queries).to eq(1)
  end
end
