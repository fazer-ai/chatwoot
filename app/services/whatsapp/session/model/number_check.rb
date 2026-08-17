# The answer to "is this number on WhatsApp?" for a single phone.
class Whatsapp::Session::Model::NumberCheck < Data.define(:phone, :exists, :address)
  include Whatsapp::Session::Model::Serializable
  coerce address: Whatsapp::Session::Model::Address
  defaults exists: false

  alias exists? exists
end
