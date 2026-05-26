require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::DailySnapshotJob do
  let!(:account_one) { create(:account) }
  let!(:account_two) { create(:account) }

  it 'runs the Calculator for every account' do
    calculator = instance_double(SuperAdmin::HealthScore::Calculator, perform: nil)
    expect(SuperAdmin::HealthScore::Calculator).to receive(:new).with(account_one, on: Date.current).and_return(calculator)
    expect(SuperAdmin::HealthScore::Calculator).to receive(:new).with(account_two, on: Date.current).and_return(calculator)
    expect(calculator).to receive(:perform).twice

    described_class.perform_now
  end

  it 'skips a failing account and continues with the rest' do
    failing = instance_double(SuperAdmin::HealthScore::Calculator)
    allow(failing).to receive(:perform).and_raise(StandardError, 'boom')

    healthy = instance_double(SuperAdmin::HealthScore::Calculator, perform: nil)

    allow(SuperAdmin::HealthScore::Calculator).to receive(:new).with(account_one, on: Date.current).and_return(failing)
    allow(SuperAdmin::HealthScore::Calculator).to receive(:new).with(account_two, on: Date.current).and_return(healthy)

    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    expect(ChatwootExceptionTracker).to receive(:new).with(kind_of(StandardError), account: account_one).and_return(tracker)

    expect { described_class.perform_now }.not_to raise_error
    expect(healthy).to have_received(:perform)
  end
end
