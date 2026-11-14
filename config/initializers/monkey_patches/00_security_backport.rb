# A security backport is a fix copied from a newer gem release for an advisory the installed
# version has no patch for. Each one registers the advisory, the gem and the version that ships
# the fix, and is applied only while the installed gem is older than that version.
# spec/initializers/monkey_patches/security_backport_spec.rb fails once the installed gem reaches
# it, so the backport and its .bundler-audit.yml entry get deleted instead of a stale copy of the
# old code overriding upstream's fix. Loaded before the other files in this directory by name.
module SecurityBackport
  Entry = Data.define(:advisory, :gem_name, :fixed_in) do
    def installed_version
      Gem.loaded_specs.fetch(gem_name).version
    end

    def needed?
      installed_version < Gem::Version.new(fixed_in)
    end
  end

  def self.entries
    @entries ||= []
  end

  # Returns whether the backport still applies, so the caller patches only then.
  def self.register(advisory:, gem_name:, fixed_in:)
    entry = Entry.new(advisory: advisory, gem_name: gem_name, fixed_in: fixed_in)
    entries << entry
    entry.needed?
  end
end
