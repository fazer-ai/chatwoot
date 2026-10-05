require 'rails_helper'

# Handled conversations are read through the builders that serve them, since the
# metric only means something as the reports compute it.
RSpec.describe Reports::HandledConversations do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bruno) { create(:user, account: account, role: :agent) }
  # Holds conversations and never replies to any of them.
  let(:diego) { create(:user, account: account, role: :agent) }
  let(:day) { Time.zone.parse('2026-09-05 12:00') }
  let(:since) { day.beginning_of_day }
  let(:until_time) { (day + 1.day).end_of_day }

  let(:shared) { create(:conversation, account: account, inbox: inbox, assignee: diego, team: team, created_at: day - 1.month) }
  let(:ana_only) { create(:conversation, account: account, inbox: other_inbox, assignee: diego, created_at: day) }

  def reply(conversation, sender, at, **attrs)
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                     message_type: :outgoing, sender: sender, created_at: at, **attrs)
  end

  before do
    travel_to day + 2.days
    reply(shared, ana, day)
    reply(shared, ana, day + 1.hour) # a second reply is still one conversation
    reply(shared, bruno, day + 1.day)
    reply(ana_only, ana, day + 2.hours)
    reply(ana_only, diego, day, private: true)
    campaign_only = create(:conversation, account: account, inbox: inbox, created_at: day)
    reply(campaign_only, bruno, day, additional_attributes: { campaign_id: 1 }) # a live chat campaign posting as Bruno
    bot_only = create(:conversation, account: account, inbox: other_inbox, created_at: day)
    create(:message, :bot_message, account: account, inbox: other_inbox, conversation: bot_only, created_at: day)
    create(:message, account: account, inbox: inbox, conversation: shared, message_type: :incoming, created_at: day)
    reply(create(:conversation, account: account, inbox: inbox, assignee: diego), bruno, day - 1.week) # out of range
  end

  def summary(builder, extra = {})
    builder.new(account: account, params: { since: since.to_i.to_s, until: until_time.to_i.to_s }.merge(extra)).build
  end

  def handled_by(rows)
    rows.to_h { |row| [row[:id], row[:handled_conversations_count]] }
  end

  describe 'agent summary' do
    it 'credits each conversation to everyone who sent it a public message, once' do
      expect(handled_by(summary(V2::Reports::AgentSummaryBuilder))).to include(ana.id => 2, bruno.id => 1, diego.id => 0)
    end

    it 'does not take the assignment for handling' do
      row = summary(V2::Reports::AgentSummaryBuilder).find { |r| r[:id] == diego.id }

      expect(row).to include(conversations_count: 1, handled_conversations_count: 0)
    end

    it 'counts only the inbox the report is narrowed to' do
      expect(handled_by(summary(V2::Reports::AgentSummaryBuilder, inbox_id: inbox.id))).to eq(ana.id => 1, bruno.id => 1)
    end
  end

  it 'counts distinct conversations per inbox and per team' do
    expect(handled_by(summary(V2::Reports::InboxSummaryBuilder))).to include(inbox.id => 1, other_inbox.id => 1)
    expect(handled_by(summary(V2::Reports::TeamSummaryBuilder))).to eq(team.id => 1)
  end

  describe 'timeseries' do
    let(:params) do
      { metric: described_class::METRIC, type: :account, since: since.to_i.to_s, until: until_time.to_i.to_s, group_by: 'day' }
    end

    it 'counts a conversation on every day it was handled' do
      values = V2::Reports::Conversations::ReportBuilder.new(account, params).timeseries.pluck(:value)

      expect(values).to eq([2, 1])
    end

    it 'counts it once over the whole period' do
      expect(V2::Reports::Conversations::ReportBuilder.new(account, params).aggregate_value).to eq(2)
    end

    it 'reads a single agent by what they sent' do
      agent_params = params.merge(type: :agent, id: bruno.id)

      expect(V2::Reports::Conversations::ReportBuilder.new(account, agent_params).timeseries.pluck(:value)).to eq([0, 1])
    end

    it 'is part of the metric cards' do
      summary = V2::Reports::Conversations::MetricBuilder.new(account, params.merge(type: :agent, id: ana.id)).summary

      expect(summary[:handled_conversations_count]).to eq(2)
    end
  end

  describe 'drilldown' do
    def drilldown(agent)
      params = { metric: described_class::METRIC, type: :agent, id: agent.id, since: since.to_i.to_s, until: until_time.to_i.to_s,
                 bucket_timestamp: since.to_i.to_s, group_by: 'day', timezone_offset: '0' }
      V2::Reports::DrilldownBuilder.new(account, params).build
    end

    it 'lists the conversations handled in the clicked bucket' do
      result = drilldown(ana)

      expect(result[:payload].map { |record| record[:conversation][:id] }).to contain_exactly(shared.id, ana_only.id)
      expect(result[:meta]).to include(record_type: 'conversation', conversation_count: 2)
    end

    it 'leaves out a conversation the agent only left a private note on' do
      expect(drilldown(diego)[:payload]).to be_empty
    end
  end
end
