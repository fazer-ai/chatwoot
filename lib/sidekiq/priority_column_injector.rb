# Rack middleware that injects a small `<script>` tag into the
# `/monitoring/sidekiq/queues` HTML response. The script (served as a
# static asset from `public/sidekiq-priority-column.js`) adds a
# "Prioridade" column to the queues table.
#
# Sidekiq 7.3 removed the `custom_javascript=` setter that earlier
# versions had, so we wire the injection at the Rack layer instead.
class Sidekiq::PriorityColumnInjector
  SCRIPT_TAG = '<script src="/sidekiq-priority-column.js"></script>'.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    return [status, headers, body] unless inject?(env, headers)

    html = collect(body)
    html = html.sub('</body>', "#{SCRIPT_TAG}\n</body>")

    new_headers = headers.dup
    new_headers['Content-Length'] = html.bytesize.to_s if new_headers.key?('Content-Length') || new_headers.key?('content-length')

    [status, new_headers, [html]]
  end

  private

  def inject?(env, headers)
    path = env['PATH_INFO'].to_s
    return false unless path.end_with?('/queues', '/queues/')

    content_type = headers['Content-Type'] || headers['content-type']
    content_type&.include?('text/html')
  end

  def collect(body)
    chunks = body.map { |chunk| chunk }
    body.close if body.respond_to?(:close)
    chunks.join
  end
end
