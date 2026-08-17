# Single error hierarchy for the session family. Every backend raises one of these, so
# controllers, jobs and the outbound path rescue one namespace instead of a
# provider-specific class.
#
# The legacy Baileys/Z-API errors inherit from ProviderUnavailable, which is what lets
# the existing rescue sites move to this namespace without changing behavior.
#
# `CODE` is the wire code from the contract's error_code enum; Errors.build maps a code
# coming off the wire back to the class.
module Whatsapp::Session::Errors
  class Error < StandardError
    CODE = 'internal'.freeze

    def code
      self.class::CODE
    end
  end

  # The provider could not be reached, or answered with something we cannot act on.
  # Anything the UI should surface as "the WhatsApp connection is not working right now"
  # lives under this class.
  class ProviderUnavailable < Error
    CODE = 'wa_error'.freeze
  end

  class Internal < ProviderUnavailable
    CODE = 'internal'.freeze
  end

  class SessionNotFound < ProviderUnavailable
    CODE = 'session_not_found'.freeze
  end

  class NotConnected < ProviderUnavailable
    CODE = 'not_connected'.freeze
  end

  class NotPaired < ProviderUnavailable
    CODE = 'not_paired'.freeze
  end

  class OwnedElsewhere < ProviderUnavailable
    CODE = 'owned_elsewhere'.freeze
  end

  class Quarantined < ProviderUnavailable
    CODE = 'quarantined'.freeze
  end

  class ClientOutdated < ProviderUnavailable
    CODE = 'client_outdated'.freeze
  end

  class Timeout < ProviderUnavailable
    CODE = 'timeout'.freeze
  end

  # A command reached its deadline before the owning instance executed it.
  class Expired < ProviderUnavailable
    CODE = 'expired'.freeze
  end

  class Unauthorized < ProviderUnavailable
    CODE = 'unauthorized'.freeze
  end

  # The backend does not declare the capability the caller asked for.
  class NotSupported < Error
    CODE = 'unsupported'.freeze
  end

  class InvalidPayload < Error
    CODE = 'invalid_payload'.freeze
  end

  class InvalidConfig < Error
    CODE = 'invalid_config'.freeze
  end

  class InvalidEvent < Error
    CODE = 'invalid_event'.freeze
  end

  class RateLimited < Error
    CODE = 'rate_limited'.freeze
  end

  class MediaTooLarge < Error
    CODE = 'media_too_large'.freeze
  end

  class MediaUnavailable < Error
    CODE = 'media_unavailable'.freeze
  end

  class RecipientNotOnWhatsapp < Error
    CODE = 'recipient_not_on_whatsapp'.freeze
  end

  class GroupParticipantNotAllowed < Error
    CODE = 'group_participant_not_allowed'.freeze
  end

  # Another worker is already handling this provider message id.
  class MessageAlreadyProcessing < Error
    CODE = 'message_already_processing'.freeze
  end

  CLASSES = [
    ProviderUnavailable, Internal, SessionNotFound, NotConnected, NotPaired, OwnedElsewhere,
    Quarantined, ClientOutdated, Timeout, Expired, Unauthorized, NotSupported, InvalidPayload,
    InvalidConfig, InvalidEvent, RateLimited, MediaTooLarge, MediaUnavailable,
    RecipientNotOnWhatsapp, GroupParticipantNotAllowed, MessageAlreadyProcessing
  ].freeze

  BY_CODE = CLASSES.index_by { |klass| klass::CODE }.freeze

  # A newer connector may answer with a code this version does not know yet. Additive
  # evolution is part of the contract, so an unknown code degrades to Internal instead
  # of blowing up the consumer thread.
  def self.build(code, message = nil)
    BY_CODE.fetch(code, Internal).new(message.presence || code)
  end
end
