# Global, install-wide language catalog used to tag a contact's preferred
# language. Read-only at the API level — rows are managed via direct DB
# inserts by Auris ops.
class Api::V1::LanguagesController < Api::BaseController
  def index
    @languages = Language.ordered
  end
end
