require 'rails_helper'

describe Import::Email::Pacer do
  # The budget stops a run and the load only pauses it: one is a daily allowance that does
  # not come back, the other is a machine that will be free again in a minute.
  it 'stops the run once the byte budget is spent' do
    pacer = described_class.new(budget_mb: 1, max_load: 99)
    expect(pacer).not_to be_over_budget
    pacer.spend(2.megabytes)
    expect(pacer).to be_over_budget
  end

  it 'reports what is left of the allowance' do
    pacer = described_class.new(budget_mb: 10, max_load: 99)
    pacer.spend(4.megabytes)
    expect(pacer.spent_mb).to be_within(0.1).of(4)
    expect(pacer.budget_mb_left).to be_within(0.1).of(6)
  end

  # Asked before a fetch, because the bytes that would break the ceiling are the ones that
  # have not been spent yet.
  it 'answers whether a transfer still fits under the ceiling' do
    pacer = described_class.new(budget_mb: 10, max_load: 99)
    pacer.spend(9.megabytes)
    expect(pacer.room_for?(1.megabyte)).to be(true)
    expect(pacer.room_for?(2.megabytes)).to be(false)
  end

  it 'does not pause a machine that is idle' do
    pacer = described_class.new(budget_mb: 10, max_load: 99)
    paused = false
    pacer.wait_for_room { paused = true }
    expect(paused).to be(false)
    expect(pacer.paused_for).to eq(0)
  end
end
