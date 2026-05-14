require 'rails_helper'

RSpec.describe V2::Reports::FunnelSummaryBuilder do
  # FunnelStage table is global (shared across accounts), so unique names keep
  # the spec deterministic across parallel runs.
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:stages) do
    {
      lead: create(:funnel_stage, name: "lead_#{SecureRandom.hex(4)}", position: 0, closed: false),
      qualified: create(:funnel_stage, name: "qualified_#{SecureRandom.hex(4)}", position: 1, closed: false),
      won: create(:funnel_stage, name: "won_#{SecureRandom.hex(4)}", position: 99, closed: true),
      lost: create(:funnel_stage, name: "lost_#{SecureRandom.hex(4)}", position: 100, closed: true)
    }
  end
  let(:params) do
    { since: 7.days.ago.to_time.to_i.to_s, until: Time.zone.now.end_of_day.to_time.to_i.to_s }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  def make_change(conversation_id:, new_stage:, created_at:, previous_stage: nil, loss_reason: nil)
    create(:funnel_stage_change,
           account: account, conversation_id: conversation_id,
           contact: contact, inbox: inbox,
           previous_stage: previous_stage, new_stage: new_stage,
           loss_reason: loss_reason, created_at: created_at)
  end

  def conversation_in(stage)
    create(:conversation, account: account, inbox: inbox, contact: contact, funnel_stage_id: stage.id)
  end

  before { stages }

  describe '#build' do
    context 'when there are no active stages' do
      before { FunnelStage.update_all(active: false) } # rubocop:disable Rails/SkipsModelValidations

      it 'returns an empty array' do
        expect(described_class.new(account: create(:account), params: params).build).to eq([])
      end
    end

    context 'when there is no activity in the period' do
      it 'returns one row per active stage with zeroed metrics' do
        report = builder.build
        lead_row = report.find { |row| row[:name] == stages[:lead].name }

        expect(lead_row).to include(
          id: stages[:lead].id, color: stages[:lead].color, closed: false,
          in_stage_count: 0, entered_count: 0, avg_time_in_stage: 0,
          won_count: 0, lost_count: 0
        )
      end

      it 'omits inactive stages' do
        inactive = create(:funnel_stage, name: "archived_#{SecureRandom.hex(4)}", position: 50, active: false)

        expect(builder.build.map { |row| row[:name] }).not_to include(inactive.name)
      end
    end

    context 'when conversations live in stages and transitions happened in the period' do
      let(:loss_reason) { create(:loss_reason, name: "price_#{SecureRandom.hex(4)}") }

      before do
        conversation_in(stages[:lead])

        in_qualified = conversation_in(stages[:qualified])
        make_change(conversation_id: in_qualified.id, new_stage: stages[:lead].name, created_at: 1.day.ago)
        make_change(conversation_id: in_qualified.id, previous_stage: stages[:lead].name,
                    new_stage: stages[:qualified].name, created_at: 1.day.ago + 2.hours)

        won = conversation_in(stages[:won])
        make_change(conversation_id: won.id, new_stage: stages[:qualified].name, created_at: 3.hours.ago)
        make_change(conversation_id: won.id, previous_stage: stages[:qualified].name,
                    new_stage: stages[:won].name, created_at: 2.hours.ago)

        lost = conversation_in(stages[:lost])
        make_change(conversation_id: lost.id, new_stage: stages[:qualified].name, created_at: 4.hours.ago)
        make_change(conversation_id: lost.id, previous_stage: stages[:qualified].name,
                    new_stage: stages[:lost].name, loss_reason: loss_reason, created_at: 1.hour.ago)
      end

      it 'counts conversations currently in each stage (snapshot, ignores period)' do
        report = builder.build
        expect(report.find { |row| row[:name] == stages[:lead].name }[:in_stage_count]).to eq(1)
        expect(report.find { |row| row[:name] == stages[:qualified].name }[:in_stage_count]).to eq(1)
      end

      it 'counts entries into each stage within the period' do
        report = builder.build
        expect(report.find { |row| row[:name] == stages[:qualified].name }[:entered_count]).to eq(3)
        expect(report.find { |row| row[:name] == stages[:won].name }[:entered_count]).to eq(1)
        expect(report.find { |row| row[:name] == stages[:lost].name }[:entered_count]).to eq(1)
      end

      it 'computes avg_time_in_stage including conversations still in stage' do
        # Three entries into qualified: one still there (~1 day spent), two
        # exited after 1h and 3h. The still-in-stage entry dominates the avg.
        avg = builder.build.find { |row| row[:name] == stages[:qualified].name }[:avg_time_in_stage]
        expect(avg).to be > 3600
      end

      it 'separates won and lost exits per previous stage' do
        qualified_row = builder.build.find { |row| row[:name] == stages[:qualified].name }
        expect(qualified_row[:won_count]).to eq(1)
        expect(qualified_row[:lost_count]).to eq(1)
      end
    end

    context 'when transitions happened outside the period' do
      before do
        old_conv = conversation_in(stages[:qualified])
        make_change(conversation_id: old_conv.id, new_stage: stages[:qualified].name, created_at: 60.days.ago)
      end

      it 'excludes them from entered_count' do
        report = builder.build
        expect(report.find { |row| row[:name] == stages[:qualified].name }[:entered_count]).to eq(0)
      end
    end
  end
end
