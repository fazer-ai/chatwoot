require 'rails_helper'

# The same question at every `client.publish` site, asked of the source rather than of a
# checklist: how long may this command hold the session?
#
# A published command has no caller waiting on it, so the `deadline` on its frame is the
# only ceiling the connector has for it, and the session's executor runs one command at a
# time -- one parked on a socket write is every send behind it parked too. A tenth publish
# site added without a ceiling would reintroduce that with nothing failing.
#
# The teardown is the deliberate exception, and it is named here rather than inferred:
# `deadline` means "do not start after this" as much as "do not run longer than this", and
# a `session.logout` dropped for arriving late leaves a device listed on the customer's
# phone. It is published precisely so it can sit pending between owners.
RSpec.describe Whatsapp::Session::Backends::Connector::Backend do
  describe 'the ceiling on every published command' do
    let(:source) { Rails.root.join('app/services/whatsapp/session/backends/connector/backend.rb') }
    let(:unbounded_on_purpose) { %w[disconnect logout delete_session] }

    # [method name, source line] for every `client.publish` call in the backend.
    let(:publish_sites) do
      method = nil
      source.readlines.each_with_object([]) do |line, sites|
        method = Regexp.last_match(1) if line =~ /^\s*def ([a-z_0-9?!]+)/
        sites << [method, line] if line.include?('client.publish(')
      end
    end

    it 'finds every publish site the backend has' do
      # Vacuity guard: a rename or a refactor that hides the calls would leave the sweep
      # passing over nothing at all.
      expect(publish_sites.size).to eq(10)
      expect(publish_sites.map(&:first).uniq)
        .to contain_exactly('disconnect', 'logout', 'delete_session', 'request_pairing_code', 'mark_read',
                            'mark_unread', 'send_chat_presence', 'update_presence', 'subscribe_presence')
    end

    it 'declares a ceiling at every publish site that is not the teardown' do
      missing = publish_sites.reject { |method, line| unbounded_on_purpose.include?(method) || line.include?('timeout:') }

      expect(missing.map(&:first)).to be_empty,
                                      "these publish a command with no ceiling: #{missing.map(&:first).uniq.join(', ')}. " \
                                      'Nobody waits on a published command, so the deadline on the frame is the only ' \
                                      'limit the connector has for it.'
    end

    it 'covers both sides of the exception' do
      # The fence proves nothing if every site is on the exception list, and nothing if none
      # is: it has to be reached by both kinds.
      bounded, unbounded = publish_sites.partition { |_, line| line.include?('timeout:') }

      expect(bounded.map(&:first).uniq).to contain_exactly('request_pairing_code', 'mark_read', 'mark_unread',
                                                           'send_chat_presence', 'update_presence', 'subscribe_presence')
      expect(unbounded.map(&:first).uniq).to match_array(unbounded_on_purpose)
    end

    it 'names methods that exist' do
      expect(described_class.instance_methods(false).map(&:to_s)).to include(*unbounded_on_purpose)
    end
  end
end
