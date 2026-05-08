class Release::CatalogService
  CONFIG_PATH = Rails.root.join('config/release_notes.yml')

  class << self
    # Returns the parsed list of releases (already capped, newest first).
    # Memoized in production; reloaded each call in development so editing the
    # YAML doesn't require a server restart.
    def all
      Rails.env.production? ? cached : load_from_disk
    end

    def latest
      all.first
    end

    def reset_cache!
      @cached = nil
    end

    private

    def cached
      @cached ||= load_from_disk
    end

    def load_from_disk
      return [] unless File.exist?(CONFIG_PATH)

      raw = YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [Time, Date, DateTime])
      Array(raw)
    rescue StandardError => e
      Rails.logger.error("Release::CatalogService failed to load #{CONFIG_PATH}: #{e.class}: #{e.message}")
      []
    end
  end
end
