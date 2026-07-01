class SwaggerController < ApplicationController
  def respond
    return head :not_found unless docs_enabled?

    # CE 4.14 security fix (#14458) — prevent path traversal by pinning
    # the resolved path inside `swagger/` before rendering. We still
    # gate the whole endpoint on `docs_enabled?` so this only executes
    # when swagger is intentionally exposed.
    swagger_root = Rails.root.join('swagger')
    file_path = swagger_root.join(derived_path).cleanpath

    return head :not_found unless file_path.to_s.start_with?("#{swagger_root}/") && file_path.file?

    render inline: file_path.read
  end

  private

  def docs_enabled?
    Rails.env.development? || Rails.env.test? || ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_SWAGGER_DOCS', false))
  end

  def derived_path
    params[:path] ||= 'index.html'
    path = Rack::Utils.clean_path_info(params[:path]).delete_prefix('/')
    path << ".#{Rack::Utils.clean_path_info(params[:format]).delete_prefix('/')}" unless path.ends_with?(params[:format].to_s)
    path
  end
end
