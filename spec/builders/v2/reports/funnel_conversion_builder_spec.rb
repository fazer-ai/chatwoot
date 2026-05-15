require 'rails_helper'

RSpec.describe V2::Reports::FunnelConversionBuilder do
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

  def conversation_with_id
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  def stage_change(conv_id:, new_stage:, created_at: 1.day.ago, previous_stage: nil, loss_reason: nil)
    create(:funnel_stage_change,
           account: account, conversation_id: conv_id,
           contact: contact, inbox: inbox,
           previous_stage: previous_stage, new_stage: new_stage,
           loss_reason: loss_reason, created_at: created_at)
  end

  before { stages }

  describe '#build' do
    context 'when there are no active stages' do
      before { FunnelStage.update_all(active: false) } # rubocop:disable Rails/SkipsModelValidations

      it 'returns empty stages, zeroed KPIs, and empty loss_reasons' do
        result = described_class.new(account: create(:account), params: params).build
        expect(result[:stages]).to eq([])
        expect(result[:kpis]).to eq(
          total_leads: 0,
          scheduling_count: 0, scheduling_rate: nil,
          confirmation_count: 0, confirmation_rate: nil,
          attendance_count: 0, attendance_rate: nil,
          no_show_count: 0, no_show_rate: nil
        )
        expect(result[:loss_reasons]).to eq([])
      end
    end

    context 'when no transitions happened in the period' do
      it 'returns one row per stage with zeroed count and nil conversion/drop-off on last' do
        result = builder.build

        lead_row = result[:stages].find { |row| row[:name] == stages[:lead].name }
        last_row = result[:stages].last
        expect(lead_row[:count]).to eq(0)
        expect(last_row[:conversion_rate]).to be_nil
        expect(last_row[:drop_off_count]).to be_nil
      end
    end

    context 'with distinct counting and conversion math' do
      before do
        # 3 distinct conversations entered "lead", one of them re-entered → still 3 distinct.
        3.times do
          conv = conversation_with_id
          stage_change(conv_id: conv.id, new_stage: stages[:lead].name)
        end
        # First conv re-entered "lead" — should NOT double count.
        first_conv = account.conversations.first
        stage_change(conv_id: first_conv.id, new_stage: stages[:lead].name, created_at: 12.hours.ago)

        # 2 of those 3 moved to qualified.
        account.conversations.limit(2).each do |conv|
          stage_change(conv_id: conv.id, previous_stage: stages[:lead].name, new_stage: stages[:qualified].name)
        end

        # 1 won, 1 lost (with loss reason).
        loss = create(:loss_reason, name: "reason_#{SecureRandom.hex(4)}")
        first_qualified = account.conversations.first
        second_qualified = account.conversations.offset(1).first
        stage_change(conv_id: first_qualified.id, previous_stage: stages[:qualified].name, new_stage: stages[:won].name)
        stage_change(conv_id: second_qualified.id, previous_stage: stages[:qualified].name,
                     new_stage: stages[:lost].name, loss_reason: loss)
      end

      it 'counts distinct conversations per stage' do
        result = builder.build
        expect(result[:stages].find { |row| row[:name] == stages[:lead].name }[:count]).to eq(3)
        expect(result[:stages].find { |row| row[:name] == stages[:qualified].name }[:count]).to eq(2)
        expect(result[:stages].find { |row| row[:name] == stages[:won].name }[:count]).to eq(1)
        expect(result[:stages].find { |row| row[:name] == stages[:lost].name }[:count]).to eq(1)
      end

      it 'computes conversion_rate as next/current and drop_off as difference' do
        result = builder.build
        lead_row = result[:stages].find { |row| row[:name] == stages[:lead].name }
        # 2 of 3 progressed from lead to qualified → 66.67% / drop-off 1.
        expect(lead_row[:conversion_rate]).to be_within(0.01).of(66.67)
        expect(lead_row[:drop_off_count]).to eq(1)
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'reports KPIs: total_leads + scheduling/confirmation/attendance/no_show rates' do
        # Point the KPI canon at the spec's random-named test stages so we can
        # exercise the math without relying on the seeder's canonical names.
        # confirmation has no matching stage in this setup — it should land
        # as zero count / nil rate so the data shape stays defined.
        stub_const('V2::Reports::FunnelConversionBuilder::CONFIRMATION_STAGE_NAME', '__no_matching_stage__')
        stub_const('V2::Reports::FunnelConversionBuilder::ATTENDANCE_STAGE_NAME', stages[:won].name)
        stub_const('V2::Reports::FunnelConversionBuilder::NO_SHOW_STAGE_NAME', stages[:lost].name)
        stages[:qualified].update!(
          chart_group: V2::Reports::FunnelConversionBuilder::SCHEDULING_CHART_GROUP
        )

        kpis = builder.build[:kpis]
        # 3 entered lead (the first open stage = total_leads denominator).
        # 2 entered qualified → scheduling = 2 → 66.67%.
        # 0 entered confirmation (no matching stage) → 0 / 0%.
        # 1 entered won → attendance = 1 → 33.33%.
        # 1 entered lost (stubbed as no-show) → no_show = 1 → 33.33%.
        expect(kpis[:total_leads]).to eq(3)
        expect(kpis[:scheduling_count]).to eq(2)
        expect(kpis[:scheduling_rate]).to be_within(0.01).of(66.67)
        expect(kpis[:confirmation_count]).to eq(0)
        expect(kpis[:confirmation_rate]).to eq(0.0)
        expect(kpis[:attendance_count]).to eq(1)
        expect(kpis[:attendance_rate]).to be_within(0.01).of(33.33)
        expect(kpis[:no_show_count]).to eq(1)
        expect(kpis[:no_show_rate]).to be_within(0.01).of(33.33)
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context 'when the next stage has more conversations than the current (entries from outside)' do
      before do
        # 1 conv into "lead", 2 distinct convs jumped straight into "qualified".
        first = conversation_with_id
        stage_change(conv_id: first.id, new_stage: stages[:lead].name)

        2.times do
          conv = conversation_with_id
          stage_change(conv_id: conv.id, new_stage: stages[:qualified].name)
        end
      end

      it 'shows conversion_rate above 100% and flags conversion_exceeds_previous' do
        result = builder.build
        lead_row = result[:stages].find { |row| row[:name] == stages[:lead].name }

        expect(lead_row[:conversion_rate]).to eq(200.0)
        expect(lead_row[:conversion_exceeds_previous]).to be true
        expect(lead_row[:drop_off_count]).to eq(0) # clamped — net influx isn't loss
      end
    end

    context 'with chart_display_name set on a stage' do
      before do
        stages[:lead].update!(chart_display_name: 'Total de leads')
        conv = conversation_with_id
        stage_change(conv_id: conv.id, new_stage: stages[:lead].name)
      end

      it 'renders the display name instead of the canonical stage name' do
        result = builder.build
        expect(result[:stages].map { |row| row[:name] }).to include('Total de leads')
        expect(result[:stages].map { |row| row[:name] }).not_to include(stages[:lead].name)
      end
    end

    context 'with chart_visible: false on a stage' do
      before do
        stages[:lost].update!(chart_visible: false)
        # A loss-flagged transition still counts toward KPIs even though
        # the lost stage is hidden from the chart.
        loss = create(:loss_reason, name: "reason_#{SecureRandom.hex(4)}")
        conv = conversation_with_id
        stage_change(conv_id: conv.id, new_stage: stages[:lost].name, loss_reason: loss)
      end

      it 'omits the hidden stage from chart rows' do
        result = builder.build
        expect(result[:stages].map { |row| row[:name] }).not_to include(stages[:lost].name)
      end

      it 'still counts the hidden closed stage toward KPIs' do
        # The hidden lost stage stands in for No-Show in the canonical
        # mapping; chart_visible=false hides it from the chart but the KPI
        # math should still see the entry.
        stub_const('V2::Reports::FunnelConversionBuilder::NO_SHOW_STAGE_NAME', stages[:lost].name)
        expect(builder.build[:kpis][:no_show_count]).to eq(1)
      end
    end

    context 'with chart_group merging multiple stages' do
      let(:agendamento_a) do
        create(:funnel_stage, name: "agendamento_a_#{SecureRandom.hex(4)}", position: 5, chart_group: 'Agendamento')
      end
      let(:agendamento_b) do
        create(:funnel_stage, name: "agendamento_b_#{SecureRandom.hex(4)}", position: 6, chart_group: 'Agendamento')
      end

      before do
        agendamento_a
        agendamento_b

        # conv_a entered only the first member.
        conv_a = conversation_with_id
        stage_change(conv_id: conv_a.id, new_stage: agendamento_a.name)

        # conv_b traversed both — must count once in the merged group.
        conv_b = conversation_with_id
        stage_change(conv_id: conv_b.id, new_stage: agendamento_a.name)
        stage_change(conv_id: conv_b.id, previous_stage: agendamento_a.name, new_stage: agendamento_b.name)
      end

      it 'collapses members into a single row keyed by the chart_group' do
        report = builder.build
        merged = report[:stages].find { |row| row[:name] == 'Agendamento' }

        expect(merged).not_to be_nil
        expect(merged[:count]).to eq(2)
        expect(report[:stages].map { |row| row[:name] }).not_to include(agendamento_a.name, agendamento_b.name)
      end
    end

    context 'with loss_reasons attached to transitions' do
      let(:reason_price) { create(:loss_reason, name: "price_#{SecureRandom.hex(4)}") }
      let(:reason_no_response) { create(:loss_reason, name: "no_response_#{SecureRandom.hex(4)}") }

      before do
        # 2 distinct convs lost to "price" (one re-entered with the same reason
        # — should NOT double-count) and 1 lost to "no response".
        conv_a = conversation_with_id
        stage_change(conv_id: conv_a.id, new_stage: stages[:lost].name, loss_reason: reason_price)
        stage_change(conv_id: conv_a.id, new_stage: stages[:lost].name, loss_reason: reason_price, created_at: 12.hours.ago)
        conv_b = conversation_with_id
        stage_change(conv_id: conv_b.id, new_stage: stages[:lost].name, loss_reason: reason_price)
        conv_c = conversation_with_id
        stage_change(conv_id: conv_c.id, new_stage: stages[:lost].name, loss_reason: reason_no_response)
      end

      it 'aggregates distinct conversations per loss reason sorted desc' do
        rows = builder.build[:loss_reasons]

        expect(rows.length).to eq(2)
        expect(rows.first[:name]).to eq(reason_price.name)
        expect(rows.first[:count]).to eq(2)
        expect(rows.first[:percentage]).to be_within(0.01).of(66.67)
        expect(rows.last[:name]).to eq(reason_no_response.name)
        expect(rows.last[:count]).to eq(1)
        expect(rows.last[:percentage]).to be_within(0.01).of(33.33)
      end

      it 'omits loss reasons with no entries in the period' do
        unused = create(:loss_reason, name: "unused_#{SecureRandom.hex(4)}")
        expect(builder.build[:loss_reasons].map { |r| r[:name] }).not_to include(unused.name)
      end
    end
  end
end
