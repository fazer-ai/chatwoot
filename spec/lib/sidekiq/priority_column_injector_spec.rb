require 'rails_helper'

RSpec.describe Sidekiq::PriorityColumnInjector do
  let(:html_body) { '<html><body><table></table></body></html>' }
  let(:html_headers) { { 'Content-Type' => 'text/html' } }
  let(:app) { ->(_env) { [200, html_headers, [html_body]] } }
  let(:middleware) { described_class.new(app) }

  def request(path: '/monitoring/sidekiq/queues')
    middleware.call('PATH_INFO' => path)
  end

  it 'injects the script tag on the queues page' do
    _status, _headers, body = request

    expect(body.first).to include(described_class::SCRIPT_TAG)
    expect(body.first).to include('</body>')
  end

  it 'updates Content-Length when the header was originally present' do
    original_length = html_body.bytesize
    expected_length = (html_body.bytesize + described_class::SCRIPT_TAG.length + 1).to_s
    headers_with_length = html_headers.merge('Content-Length' => original_length.to_s)
    app = ->(_env) { [200, headers_with_length, [html_body]] }

    _status, headers, _body = described_class.new(app).call('PATH_INFO' => '/monitoring/sidekiq/queues')

    expect(headers['Content-Length']).to eq(expected_length)
  end

  it 'leaves non-queues paths untouched' do
    _status, _headers, body = request(path: '/monitoring/sidekiq/busy')

    expect(body.first).to eq(html_body)
  end

  it 'leaves non-HTML responses untouched' do
    json_app = ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{}']] }
    _status, _headers, body = described_class.new(json_app).call('PATH_INFO' => '/monitoring/sidekiq/queues')

    expect(body.first).to eq('{}')
  end
end
