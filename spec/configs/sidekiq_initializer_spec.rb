require 'rails_helper'

# Regression guard: the sidekiq initializer loads cron entries from
# `config/schedule.yml` into Redis. Historically the loader was gated on
# `Sidekiq.server?`, which meant only the sidekiq process registered
# crons — a real problem during rolling deploys where the web container
# restarts but the sidekiq container survives untouched, leaving new
# schedule.yml entries unregistered in Redis until the sidekiq container
# eventually bounces. Real incident: `super_admin_health_score_daily_snapshot_job`
# was added in commit 6248fb2ee (25/05/2026), ran once the next day and
# then silently sat unregistered for ~2.5 months. Any process (web,
# sidekiq server, console, rake) now registers crons on boot.
RSpec.describe 'config/initializers/sidekiq.rb' do # rubocop:disable RSpec/DescribeClass
  let(:initializer_source) { File.read(Rails.root.join('config/initializers/sidekiq.rb')) }
  let(:reloader_block) { initializer_source[/reloader\.to_prepare do.*?^end/m] }

  it 'calls Sidekiq::Cron::Job.load_from_hash! inside the reloader block' do
    expect(reloader_block).not_to be_nil
    expect(reloader_block).to include('Sidekiq::Cron::Job.load_from_hash!')
  end

  it 'does not guard the cron loader on `Sidekiq.server?`' do
    # Only checks actual code lines — comments are allowed to reference the
    # guard by name (they do, to explain why it was removed).
    code_only = reloader_block.each_line.reject { |line| line.strip.start_with?('#') }.join
    expect(code_only).not_to(match(/Sidekiq\.server\?/),
                             'Reintroducing the Sidekiq.server? guard leaves cron entries unregistered when only web ' \
                             'containers restart (see incident with super_admin_health_score_daily_snapshot_job).')
  end
end
