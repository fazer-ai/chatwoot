require 'rails_helper'
require 'prism'

# fazer_ai_ee/ changes Enterprise behavior without touching enterprise/, so an upstream merge
# can change what an override sits on top of without any conflict to point at it. These
# checks turn that into a failure: whoever merges upstream re-reads the override, then
# updates the fingerprint here.
RSpec.describe 'fazer_ai_ee overrides of upstream Enterprise code' do # rubocop:disable RSpec/DescribeClass
  def def_nodes(path)
    stack = [Prism.parse(Rails.root.join(path).read).value]
    nodes = []
    until stack.empty?
      node = stack.pop
      stack.concat(node.compact_child_nodes)
      nodes << node if node.is_a?(Prism::DefNode)
    end
    nodes
  end

  def fingerprint(text)
    Digest::SHA256.hexdigest(text)[0, 16]
  end

  # Methods copied whole into fazer_ai_ee because the change sits in the middle of them. An
  # upstream change to the original would otherwise be silently shadowed by the stale copy.
  copied_methods = {
    'enterprise/app/mailers/enterprise/agent_notifications/conversation_notifications_mailer.rb' => {
      sla_missed_first_response: 'a95a4c29d517389a',
      sla_missed_next_response: '4962c62cf37fa5d1',
      sla_missed_resolution: 'f4bbbb4845d83cef'
    },
    'enterprise/app/services/voice/outbound_call_builder.rb' => { perform!: '2bfecf7dd5e964e3' },
    'enterprise/app/controllers/api/v1/accounts/whatsapp_calls_controller.rb' => { create_outbound_call: '3f772e2a424aa6ff' }
  }

  # Views copied whole into fazer_ai_ee/app/views, which win over enterprise/app/views.
  copied_views = {
    'api/v1/accounts/applied_slas/download.csv.erb' => '91da5f3545ba86b9',
    'devise/mailer/confirmation_instructions.html.erb' => '23467a029540f730',
    'super_admin/accounts/_form.html.erb' => 'db7b68f9b20ac7af'
  }

  copied_methods.each do |path, methods|
    methods.each do |name, expected|
      it "still copies the upstream #{name} in #{path}" do
        node = def_nodes(path).find { |candidate| candidate.name == name && candidate.receiver.nil? }

        expect(node).to be_present
        expect(fingerprint(node.slice)).to eq(expected)
      end
    end
  end

  copied_views.each do |view, expected|
    it "still copies the upstream view #{view}" do
      expect(fingerprint(Rails.root.join('enterprise/app/views', view).read)).to eq(expected)
      expect(Rails.root.join('fazer_ai_ee/app/views', view)).to exist
    end
  end

  # Every override module is in front of its target, and every method in it that calls
  # `super` still has an upstream method to reach: a rename upstream would otherwise leave
  # the override answering for a method nobody calls anymore.
  it 'sits in front of each target and reaches an upstream method wherever it calls super' do
    overrides = Rails.root.glob('fazer_ai_ee/app/*/fazer_ai_ee/**/*.rb').map do |path|
      relative = path.relative_path_from(Rails.root.join('fazer_ai_ee/app')).to_s.split('/', 2).last
      [relative.delete_suffix('.rb').camelize, path]
    end
    expect(overrides).not_to be_empty

    unreachable = overrides.flat_map do |module_name, path|
      mod = module_name.constantize
      # Enterprise mixes its plan limits into Account under a name CE does not have.
      target = (module_name == 'FazerAiEe::Account::PlanUsageAndLimits' ? 'Account' : module_name.delete_prefix('FazerAiEe::')).constantize
      expect(target.ancestors).to include(mod)

      def_nodes(path.relative_path_from(Rails.root).to_s).filter_map do |node|
        next if node.receiver || node.slice.exclude?('super')

        method = node.name == :initialize ? target.allocate.method(:initialize) : target.instance_method(node.name)
        next unless method.owner == mod # a class method, prepended on the singleton class

        "#{module_name}##{node.name}" if method.super_method.nil?
      end
    end

    expect(unreachable).to be_empty
  end

  it 'only skips upstream examples that upstream still has' do
    FazerAiEe::SUPERSEDED_UPSTREAM_EXAMPLES.each do |file, examples|
      source = Rails.root.join(file).read
      examples.each_key { |description| expect(source).to include("it '#{description}'") }
    end
  end
end
