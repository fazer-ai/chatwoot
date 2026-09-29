require 'rails_helper'

# Nobody gives a slot back when its holder died, or when nothing is importing at all, and
# then only this wakes the batches that are waiting.
RSpec.describe Whatsapp::Baileys::HistoryImportWakeJob do
  it 'tops the import slots up from the waiting queue' do
    allow(Whatsapp::Session::Inbound::ImportSlots).to receive(:top_up)

    described_class.perform_now

    expect(Whatsapp::Session::Inbound::ImportSlots).to have_received(:top_up)
      .with(into: Whatsapp::Baileys::HistoryImportJob.queue_name)
  end

  it 'runs every minute' do
    schedule = YAML.safe_load(Rails.root.join('config/schedule.yml').read)
    entry = schedule.values.find { |job| job['class'] == described_class.name }

    expect(entry).to include('cron' => '* * * * *')
  end
end
