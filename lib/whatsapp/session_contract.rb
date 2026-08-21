# Access to the vendored copy of the WhatsApp session protocol contract, shared by the
# specs (which validate every canonical payload against it) and by the rake tasks that
# sync it and check it for drift.
#
# The contract itself lives in fazer-ai/whatsapp-connector: the connector is what
# produces events, so it owns the schema. This copy is pinned by CONTRACT_REF.
module Whatsapp::SessionContract
  ROOT = 'spec/fixtures/whatsapp/session/contract'.freeze
  REFERENCE_FILE = 'CONTRACT_REF'.freeze

  class << self
    def root
      Rails.root.join(ROOT)
    end

    def protocol_version
      root.join('PROTOCOL_VERSION').read.strip.to_i
    end

    def schema
      @schema ||= JSON.parse(root.join('schema/protocol.schema.json').read)
    end

    def event_validator
      @event_validator ||= validator_for('event')
    end

    def command_validator
      @command_validator ||= validator_for('command')
    end

    def fixtures(kind)
      Dir[root.join("fixtures/#{kind}/*.json")]
    end

    def fixture(kind, name)
      JSON.parse(root.join("fixtures/#{kind}/#{name}.json").read)
    end

    # Content hash of every vendored file, so a drift check does not depend on git.
    # CONTRACT_REF itself is excluded: it stores the result.
    def checksum(directory = root)
      files = Dir.glob("#{directory}/**/*").select { |path| File.file?(path) && File.basename(path) != REFERENCE_FILE }.sort
      digest = files.sum('') do |path|
        "#{Pathname.new(path).relative_path_from(directory)}\0#{File.read(path)}\0"
      end
      Digest::SHA256.hexdigest(digest)
    end

    # Parsed CONTRACT_REF: which connector commit this copy came from, and the checksum
    # it had at that point.
    def reference
      root.join(REFERENCE_FILE).read.lines.to_h do |line|
        key, value = line.strip.split('=', 2)
        [key, value]
      end
    end

    def drifted?
      reference['checksum'] != checksum
    end

    def write_reference(repo:, ref:)
      root.join(REFERENCE_FILE).write("repo=#{repo}\nref=#{ref}\nchecksum=#{checksum}\n")
    end

    private

    # json_schemer resolves $ref against the document root, so a sub-schema is validated
    # by pointing a tiny wrapper document at it.
    def validator_for(definition)
      JSONSchemer.schema({ '$ref' => "#/definitions/#{definition}", 'definitions' => schema['definitions'] })
    end
  end
end
