require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Locks do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:chat) { '5541999990000' }
  let(:message_id) { '3EB0AAAA0001' }

  describe '.with_chat_lock' do
    it 'runs the block and releases the chat' do
      expect(described_class.with_chat_lock(inbox, chat) { :done }).to eq(:done)
      expect(Redis::Alfred.get(described_class.chat_key(inbox, chat))).to be_nil
    end

    it 'refuses a chat another worker holds' do
      described_class.with_chat_lock(inbox, chat) do
        expect { described_class.with_chat_lock(inbox, chat) { :nested } }.to raise_error(described_class::Busy)
      end
    end

    # WhatsApp names the same 1:1 peer by phone in one event and by LID in the next, and
    # both resolve to one contact: locking only the id an event carries let a worker
    # holding the other alias run alongside, and each opened a conversation of its own.
    it 'refuses a chat another worker holds under a different alias' do
      described_class.with_chat_lock(inbox, %w[5541999990000 182736451928374]) do
        expect { described_class.with_chat_lock(inbox, '182736451928374') { :nested } }
          .to raise_error(described_class::Busy)
      end
    end

    it 'releases every alias it took' do
      described_class.with_chat_lock(inbox, %w[5541999990000 182736451928374]) { :done }

      expect(Redis::Alfred.get(described_class.chat_key(inbox, '182736451928374'))).to be_nil
      expect(Redis::Alfred.get(described_class.chat_key(inbox, '5541999990000'))).to be_nil
    end

    # The second alias being held is a Busy for the whole call, and the first must not be
    # left behind: the next delivery would find it locked by nobody until the TTL.
    it 'releases what it took when a later alias is already held' do
      Redis::Alfred.set(described_class.chat_key(inbox, '182736451928374'), 'other', ex: 30)

      expect { described_class.with_chat_lock(inbox, %w[5541999990000 182736451928374]) { :never } }
        .to raise_error(described_class::Busy)

      expect(Redis::Alfred.get(described_class.chat_key(inbox, '5541999990000'))).to be_nil
    end

    # An operation that outran the TTL, syncing a large group roster being the realistic
    # one, used to delete the lock a second worker had already taken: from there the two
    # interleave their conversation, membership and activity writes.
    it 'leaves a lock another worker took over in place' do
      key = described_class.chat_key(inbox, chat)

      described_class.with_chat_lock(inbox, chat) do
        Redis::Alfred.delete(key)
        Redis::Alfred.set(key, 'another-worker', ex: 30)
      end

      expect(Redis::Alfred.get(key)).to eq('another-worker')
    end
  end

  describe '.with_message_lock' do
    it 'releases the marker so a later pass can run' do
      described_class.with_message_lock(inbox, message_id) { :first }

      expect(described_class.with_message_lock(inbox, message_id) { :second }).to eq(:second)
    end

    # Answering ":duplicate" here acknowledges the event: a worker killed between taking
    # the marker and writing the row would turn its own retry into a lost message. What
    # makes a finished message a duplicate is its stored source_id, which the caller
    # checks inside the block.
    it 'asks for a retry while the marker is held instead of calling it a duplicate' do
      Redis::Alfred.set(described_class.message_key(inbox, message_id), true, ex: 30)

      expect { described_class.with_message_lock(inbox, message_id) { :ran } }.to raise_error(described_class::Busy)
    end

    # Same failure the chat lock had: a pass that outran the TTL deleted the marker a
    # redelivery had already taken, and a third delivery could then run alongside it.
    it 'leaves a marker another worker took over in place' do
      key = described_class.message_key(inbox, message_id)

      described_class.with_message_lock(inbox, message_id) do
        Redis::Alfred.delete(key)
        Redis::Alfred.set(key, 'another-worker', ex: 30)
      end

      expect(Redis::Alfred.get(key)).to eq('another-worker')
    end

    it 'runs unguarded when there is no id to key on' do
      expect(described_class.with_message_lock(inbox, nil) { :ran }).to eq(:ran)
    end
  end
end
