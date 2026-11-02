# A visitor on a public channel can type an email or a phone number, and upstream joins the session
# to whichever contact of the account already holds that value: ContactIdentifyAction merges into
# it, and ContactInboxWithContactBuilder hands a brand-new public API session that contact outright.
# Nothing in those requests proves the visitor is that person, so typing a customer's phone number
# was enough to become the customer: the session lands on their contact, an agent bot's HTTP tools
# get their contact_id and phone, and the human agent reads the visitor's messages under the
# customer's name. Upstream closed the case where the existing contact carries an identifier
# (chatwoot/chatwoot#14935); a contact that came in through WhatsApp or an API inbox carries none.
#
# Inside those requests a value that already belongs to another contact is therefore not used to
# find or merge one. It stays on the visitor as an unverified claim in
# additional_attributes (`claimed_email`, `claimed_phone_number`), which agents can read and act on
# by merging the contacts by hand once they have checked. A value nobody holds is saved as before.
#
# That holds with a valid identifier_hash too: the site signs the identifier and nothing else, so a
# signed-in visitor could otherwise send their own identifier and hash next to someone else's phone.
# The identifier keeps finding and merging its contact as upstream does, signed or, where the inbox
# leaves HMAC optional, unsigned (upstream's contract for setUser without identity validation).
#
# Module prepends rather than edits to upstream files, so an upstream sync never conflicts here
# (config/initializers/unproven_contact_merge_guard.rb).
module UnprovenContactMergeGuard
  CLAIM_PREFIX = 'claimed_'.freeze

  class Context < ActiveSupport::CurrentAttributes
    attribute :unproven
  end

  def self.unproven(&)
    Context.set(unproven: true, &)
  end

  def self.unproven?
    Context.unproven == true
  end

  module IdentifyAction
    private

    def merge_if_existing_email_contact
      return super unless UnprovenContactMergeGuard.unproven? && someone_else?(existing_email_contact)

      hold_back_claim(:email)
    end

    def merge_if_existing_phone_number_contact
      return super unless UnprovenContactMergeGuard.unproven? && someone_else?(existing_phone_number_contact)

      hold_back_claim(:phone_number)
    end

    def someone_else?(existing_contact)
      existing_contact.present? && existing_contact.id != @contact.id
    end

    def hold_back_claim(key)
      @attributes_to_update.delete(key)
      (@held_back_claims ||= {})["#{CLAIM_PREFIX}#{key}"] = params[key]
    end

    def additional_attributes
      return super if @held_back_claims.blank?

      (super || {}).merge(@held_back_claims)
    end
  end

  module ContactBuilder
    private

    # Only the identifier finds an existing contact here, under the caller's HMAC rules.
    def find_contact
      return super unless UnprovenContactMergeGuard.unproven?

      find_contact_by_identifier(contact_attributes[:identifier])
    end

    def create_contact
      return super unless UnprovenContactMergeGuard.unproven?

      taken = taken_contact_details
      return super if taken.empty?

      claims = taken.to_h { |key| ["#{CLAIM_PREFIX}#{key}", contact_attributes[key]] }
      @contact_attributes = contact_attributes.merge(taken.index_with(nil)).merge(
        additional_attributes: (contact_attributes[:additional_attributes] || {}).to_h.merge(claims)
      )
      super
    end

    def taken_contact_details
      phone_number = contact_attributes[:phone_number]
      taken = []
      taken << :email if find_contact_by_email(contact_attributes[:email])
      taken << :phone_number if phone_number.present? && account.contacts.exists?(phone_number: phone_number)
      taken
    end
  end

  module WidgetContacts
    def update
      UnprovenContactMergeGuard.unproven { super }
    end

    def set_user
      UnprovenContactMergeGuard.unproven { super }
    end
  end

  module WidgetConversations
    def process_update_contact
      UnprovenContactMergeGuard.unproven { super }
    end
  end

  module WidgetMessages
    def update
      UnprovenContactMergeGuard.unproven { super }
    end
  end

  module PublicContacts
    def create
      UnprovenContactMergeGuard.unproven { super }
    end

    def update
      UnprovenContactMergeGuard.unproven { super }
    end
  end

  # The email collect card asks a visitor whose contact has no email. One whose email was held back
  # as a claim already answered, and asking again would only collect the same claim.
  module EmailCollect
    private

    def contact_has_email?
      super || contact.additional_attributes&.dig("#{CLAIM_PREFIX}email").present?
    end
  end
end
