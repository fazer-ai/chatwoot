class SwaggerController < ApplicationController
  def respond
    # Redirect /swagger to /swagger/ for proper relative path resolution
    # Only redirect if no path param (i.e., accessing the root) and no trailing slash
    return redirect_to('/swagger/', status: :moved_permanently) if params[:path].blank? && !request.original_fullpath.end_with?('/')

    if Rails.env.development? || Rails.env.test?
      render inline: Rails.root.join('swagger', derived_path).read
    else
      head :not_found
    end
  end

  private

  def derived_path
    params[:path] ||= 'index.html'
    path = Rack::Utils.clean_path_info(params[:path])
    path << ".#{Rack::Utils.clean_path_info(params[:format])}" unless path.ends_with?(params[:format].to_s)
    path
  end
end
