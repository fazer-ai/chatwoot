class Api::V1::ReleasesController < Api::BaseController
  def index
    @releases = ::Release::CatalogService.all
  end
end
