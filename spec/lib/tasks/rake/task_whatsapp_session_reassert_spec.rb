require 'rake'
require 'rails_helper'

# The deploy step behind fazer-ai/whatsapp-connector#194. The connector's resume sweep reads
# which accounts should be up from a table only a `session.connect` writes, and the upgrade that
# introduces the sweep creates that table empty: the fleet it was built to recover is the one it
# cannot see. This is the side that knows, saying so once.
RSpec.describe Rake::Task do
  subject(:task) { described_class['whatsapp:session:reassert'] }

  let(:account) { create(:account) }

  before do
    described_class.clear
    Chatwoot::Application.load_tasks
    # The pacing is real and this is a spec: without this the examples would sit out the pause.
    allow_any_instance_of(Object).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  def native_channel(connection)
    create(:channel_whatsapp, provider: 'native', account: account,
                              validate_provider_config: false, sync_templates: false).tap do |channel|
      # update_column rather than update!: provider_connection is written by the state writer in
      # production, and going through validations here would drag a provider call into a fixture.
      channel.update_column(:provider_connection, # rubocop:disable Rails/SkipsModelValidations
                            { 'connection' => connection, 'phone_number' => '5511999999999' })
    end
  end

  it 'asks only the native inboxes this installation records as connected' do
    open_channel = native_channel('open')
    closed_channel = native_channel('close')
    asked = []
    allow_any_instance_of(Channel::Whatsapp).to receive(:setup_channel_provider) { |channel| asked << channel.id } # rubocop:disable RSpec/AnyInstance

    task.invoke

    expect(asked).to eq([open_channel.id])
    expect(asked).not_to include(closed_channel.id)
  end

  # A provider that will not answer for one inbox is the state this task runs in the middle of,
  # so stopping at the first failure would leave the rest of the fleet down -- which is the very
  # thing it exists to end.
  it 'goes on to the next inbox when one cannot be asked' do
    first = native_channel('open')
    second = native_channel('open')
    asked = []
    allow_any_instance_of(Channel::Whatsapp).to receive(:setup_channel_provider) do |channel| # rubocop:disable RSpec/AnyInstance
      raise Whatsapp::Session::Errors::ProviderUnavailable, 'nope' if channel.id == first.id

      asked << channel.id
    end

    expect { task.invoke }.not_to raise_error
    expect(asked).to eq([second.id])
  end

  it 'says there is nothing to do rather than asking anything' do
    native_channel('close')
    allow_any_instance_of(Channel::Whatsapp).to receive(:setup_channel_provider) # rubocop:disable RSpec/AnyInstance

    expect { task.invoke }.to output(/nothing to re-assert/).to_stdout
  end

  # The control stream is one for the whole fleet, so the batch size is not a convenience: a wake
  # per inbox in the same second is the stampede it cannot absorb.
  it 'waits between batches, and not before the first one' do
    3.times { native_channel('open') }
    allow_any_instance_of(Channel::Whatsapp).to receive(:setup_channel_provider) # rubocop:disable RSpec/AnyInstance
    pauses = []
    allow_any_instance_of(Object).to receive(:sleep) { |_, seconds| pauses << seconds } # rubocop:disable RSpec/AnyInstance

    task.invoke(1, 7)

    expect(pauses).to eq([7.0, 7.0])
  end
end
