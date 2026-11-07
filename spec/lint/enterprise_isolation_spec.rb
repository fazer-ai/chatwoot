require 'rails_helper'
require 'open3'

# The fork ships Enterprise as upstream publishes it: nothing outside enterprise/ reopens or
# patches it. bin/validate_enterprise_isolation reads the source for that; this runs it, and
# adds what only the loaded app can tell, because a prepend aimed at a CE class can still
# land on a method Enterprise put there (Attachment's audio transcription is one).
RSpec.describe 'Enterprise isolation' do # rubocop:disable RSpec/DescribeClass
  enterprise_root = Rails.root.join('enterprise').to_s

  it 'finds no overlay, no reopened Enterprise constant and no patch aimed at one' do
    output, status = Open3.capture2e(Rails.root.join('bin/validate_enterprise_isolation').to_s)

    expect(status).to be_success, output
  end

  context 'with enterprise/ loaded', if: ChatwootApp.enterprise? do
    # The method a prepended module's own definition stands in front of, which is the one that
    # runs when it calls `super`.
    def overridden(klass, mod, name)
      method = klass.instance_method(name)
      method = method.super_method while method && method.owner != mod
      method&.super_method
    end

    def from_enterprise?(source, root)
      source.present? && source.first.start_with?("#{root}/")
    end

    it 'prepends nothing from CE code over a method Enterprise defines' do
      Rails.application.eager_load!
      # Read through Module's own methods: a class is free to define `name` or `ancestors`
      # of its own, and some in the bundle do.
      name_of = Module.instance_method(:name)
      ancestors_of = Module.instance_method(:ancestors)

      overrides = ObjectSpace.each_object(Module).flat_map do |klass|
        next([]) if klass.singleton_class? || name_of.bind_call(klass).nil?

        ancestors_of.bind_call(klass).take_while { |ancestor| ancestor != klass }.flat_map do |mod|
          next([]) if name_of.bind_call(mod).to_s.start_with?('Enterprise::')

          (mod.instance_methods(false) + mod.private_instance_methods(false)).filter_map do |method_name|
            next if from_enterprise?(mod.instance_method(method_name).source_location, enterprise_root)

            target = overridden(klass, mod, method_name)
            next unless target && from_enterprise?(target.source_location, enterprise_root)

            "#{name_of.bind_call(mod) || mod.inspect}##{method_name} over #{target.owner}"
          end
        end
      end

      expect(overrides.uniq).to be_empty
    end
  end
end
