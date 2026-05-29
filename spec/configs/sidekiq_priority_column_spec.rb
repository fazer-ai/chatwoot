require 'rails_helper'

# Prevents drift between `config/sidekiq.yml` (source of truth for queue
# priority ordering at runtime) and the hardcoded list in
# `public/sidekiq-priority-column.js` (consumed by the Sidekiq Web UI to
# render the "Prioridade" column on /monitoring/sidekiq/queues).
RSpec.describe 'sidekiq priority column' do # rubocop:disable RSpec/DescribeClass
  it 'lists queues in the same order as config/sidekiq.yml' do
    yaml = YAML.unsafe_load(ERB.new(File.read(Rails.root.join('config/sidekiq.yml'))).result)
    yaml_queues = yaml[:queues]

    js = File.read(Rails.public_path.join('sidekiq-priority-column.js'))
    js_queues = js[/const PRIORITY_ORDER = \[(.*?)\];/m, 1]
                .scan(/'([^']+)'/)
                .flatten

    expect(js_queues).to eq(yaml_queues),
                         lambda {
                           "Drift between config/sidekiq.yml and public/sidekiq-priority-column.js.\n" \
                             "YAML: #{yaml_queues}\nJS:   #{js_queues}"
                         }
  end
end
