# frozen_string_literal: true

# fazer.ai Hub Mock Server
#
# This creates a local mock server that responds to subscription requests.
# Used for development testing of different subscription states.
#
# Usage:
#   1. Add to your .env:       FAZER_AI_HUB_URL=http://localhost:3099
#   2. Restart Chatwoot
#   3. Start the mock server:  ruby spec/support/mocks/fazer_ai_hub_mock_server.rb
#   4. Open http://localhost:3099 to change subscription state
#
# You can change the subscription state via:
#   - Browser UI: http://localhost:3099
#   - curl commands:
#       curl -X POST http://localhost:3099/set_state -d 'state=trialing&days=7'
#       curl -X POST http://localhost:3099/set_state -d 'state=active'
#       curl -X POST http://localhost:3099/set_state -d 'state=past_due'
#       curl -X POST http://localhost:3099/set_state -d 'state=canceling&days=30'
#       curl -X POST http://localhost:3099/set_state -d 'state=inactive'
#       curl -X POST http://localhost:3099/set_state -d 'state=network_error'
#
# After changing state, you MUST trigger a sync:
#   - Navigate to Super Admin > Settings
#   - Click "Refresh" on the fazer.ai subscription section
#
# NOTE: This file is a STANDALONE Ruby script that runs OUTSIDE of Rails.
# It does not load ActiveSupport, so we use plain Ruby methods (Time.now, etc.)
# The test public key is automatically used when FAZER_AI_HUB_URL points to localhost.

# rubocop:disable Rails/TimeZone, Rails/Blank, Lint/MissingCopEnableDirective
require 'bundler/setup'
require 'jwt'
require 'json'
require 'openssl'
require 'uri'
require 'socket'

# rubocop:disable Metrics/ClassLength
class FazerAiHubMockServer
  PORT = 3099

  # Test private key - matches FazerAi::SubscriptionToken::TEST_PUBLIC_KEY
  PRIVATE_KEY = <<~PEM
    -----BEGIN RSA PRIVATE KEY-----
    MIIEogIBAAKCAQEAr9ICjCbXqQxIS7jmSaeG5ifkpEzM0dc9/YCmTW/wVClVDpgR
    CUpNgCeXG45PX8/LDa1JLgoyeBjCdaHMgLpb1I9ssWCMKBXOfHd9HsswCosWacbw
    iM7ZiLhByAh1KgUAYV5KTbGgJM9Bf/JPv6L4b08FRb67OO4gdQxRQljY5ibj8MfF
    1NeB9c6PKWa41CAhkVGr+bktoL8lfQ357a2FN8o2wr/TzlH/SvTK7GZp61ZBJQ9h
    sKuxvQ0IBib2kem2aHEvRtMZ2AIrTCkmspAJReAtw7sC/gVAheqw0qGcYBQsF4gK
    06L60oj8NAra1diA+WPlCE3wD5365iaZLmIfTQIDAQABAoIBACxrfQxGpfbGLR/A
    a6IRKrJMQuZFpvufC0DYN2vaC5hfxucEgU1dEd5+Yh1qo2AcAfuHG7V/iwevjbWl
    dqLRMnEt+TKJJ2/bLotgruJQSGdpg3Se99dAl1IE502v4VYH5HQ1G8WsSj7yg+Rc
    5kwO0wBgMP9RdECqXNXlkkQWaVof7axPTdlT7Ysa3xiGFbU2+nw+HwITbfvZ713h
    pGKP5tGjSQP/bYx1Ft/3Ko9RBa/jFRQblGeqZK0if+Ya9Xo97Jt9UYSlQ5nJxzgd
    Z6Sh0eOLDn+OBsFaAzEjyQQSq4lB1+ihHJ9QLHKxVl9Vu1m4jBMGVY7ZhaZIl7L4
    sdGCeisCgYEAtR7YH7FNYWaAUNrhNg36aW9tRrX4jRbJukU/WuQBymTp2ezUmrrM
    KDu9m7ajRZbO6GyIlYYZsSv0ww9ylALvxk+G59zwBHzTjGdsnX3oWvWe/WtnDxmL
    qi8qvphh084Kw0xUnpRgUBAV5Pglcu4fAos9P9cXwkymFBJ5CSdy1MsCgYEA+II3
    2cULMTAYsK7flam9+pDpAcK2sTuUOdRt/e2cpi6tFTziUQkHu5lwTkGqiwCN6wsY
    U5hy72t3kngr+gWQ15umKgmqzPNC1BT5RYX9VgYmTRICe4NN8H2+U/3I9EXaa4Pu
    i/WXMo7X2dGy4iCTx33Mlv72FYV1reuw49ji8UcCgYBKuG/XG1FeFmhncvUoVLnz
    F2oQmu/wXO9aLklF2Py4H8uuARtwvhGNo5/EhqNzCRVRI71xWkJtKkIu2sedMlzz
    BkoUi7xlTY4ExYI0swXRyLUPvWhl/Vb2HcFXogvx0nX0PiBGz9WwEgLGVG02rfAT
    H5hkJvuBSBfX/gr68NBZ4wKBgFxSLCOH82d7ocCJxuBX5g8fJKEV0D85jhCJ3a73
    RjnqnzyDmORYAXptP26jMJNhSlfmkEwGF7TgbNSKNnQ0+yFOXsXBP6XSPaKChDSS
    2ZHKyRHavfdayWqtnDah0rUE+mb05Xszas9Kh+AQ6m7dgWkcUBRMdel64kQRim6r
    FWxjAoGAPUmcseD1gH1aBtuHbImAyNf23TmSz7gw0brAnBBZvfeFygnroRxOCCHR
    n43XElACl8pjztjLwu8qI3b6tD9eC8OVtP6YlOYRez5qysrkbKDsL5c7IlwKb/69
    xCawpgCRGTTzTgfMQJP6ac/A5ACWs0FMjG3M1zW5n5lqlZ7H95Q=
    -----END RSA PRIVATE KEY-----
  PEM

  UI_HTML = <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>fazer.ai Mock Server</title>
      <style>
        body { font-family: system-ui; max-width: 700px; margin: 50px auto; padding: 20px; }
        h1 { color: #333; }
        .btn { padding: 10px 20px; margin: 5px; cursor: pointer; border: none; border-radius: 5px; font-size: 14px; }
        .active { background: #22c55e; color: white; }
        .trialing { background: #3b82f6; color: white; }
        .past_due { background: #f59e0b; color: white; }
        .canceling { background: #f97316; color: white; }
        .inactive { background: #ef4444; color: white; }
        .network_error { background: #6b7280; color: white; }
        .status { padding: 20px; background: #f3f4f6; border-radius: 8px; margin: 20px 0; font-family: monospace; white-space: pre; }
        code { background: #e5e7eb; padding: 2px 6px; border-radius: 4px; }
        .warning { background: #fef3c7; border: 1px solid #f59e0b; padding: 12px; border-radius: 8px; margin: 20px 0; }
        .sync-btn { background: #6366f1; color: white; margin-top: 10px; }
      </style>
    </head>
    <body>
      <h1>🎭 fazer.ai Hub Mock Server</h1>
      <p>Click a button to change the subscription state:</p>

      <div>
        <button class="btn active" onclick="setState('active')">Active</button>
        <button class="btn trialing" onclick="setState('trialing', prompt('Days remaining:', '14'))">Trialing</button>
        <button class="btn past_due" onclick="setState('past_due')">Past Due</button>
        <button class="btn canceling" onclick="setState('canceling', prompt('Days until cancel:', '30'))">Canceling</button>
        <button class="btn inactive" onclick="setState('inactive')">Inactive</button>
        <button class="btn network_error" onclick="setState('network_error')">Network Error</button>
      </div>

      <div class="status" id="status">Loading...</div>

      <div class="warning">
        <strong>⚠️ Important:</strong> After changing the state, you must trigger a sync!
        <br><br>
        Navigate to <strong>Super Admin &gt; Settings</strong> and click "Refresh" on the fazer.ai subscription section.
      </div>

      <h3>📋 Setup Instructions</h3>
      <ol>
        <li>Set <code>FAZER_AI_HUB_URL=http://localhost:3099</code> in your .env</li>
        <li>Restart Chatwoot</li>
        <li>Change state using buttons above</li>
        <li>Go to Super Admin > Settings, click "Refresh" on fazer.ai subscription</li>
      </ol>

      <script>
        async function setState(state, days) {
          if (days === null) return;
          const body = new URLSearchParams({ state, days: days || 30 });
          await fetch('/set_state', { method: 'POST', body });
          loadStatus();
        }

        async function loadStatus() {
          const res = await fetch('/status');
          const data = await res.json();
          document.getElementById('status').textContent =
            'Current State: ' + JSON.stringify(data.current_state, null, 2);
        }

        loadStatus();
      </script>
    </body>
    </html>
  HTML

  attr_accessor :current_state

  def initialize
    @current_state = default_state
  end

  def run
    print_banner
    start_server
  end

  private

  def default_state
    {
      status: 'active',
      cancel_at_period_end: false,
      current_period_end: (Time.now + (30 * 24 * 60 * 60)).to_i,
      simulate_error: false
    }
  end

  def generate_token(installation_identifier = 'test')
    private_key = OpenSSL::PKey::RSA.new(PRIVATE_KEY)

    payload = {
      status: @current_state[:status],
      instance_type: 'chatwoot',
      installation_identifier: installation_identifier,
      features: { 'kanban' => { 'account_limit' => 5 } },
      cancel_at_period_end: @current_state[:cancel_at_period_end],
      current_period_end: @current_state[:current_period_end],
      iat: Time.now.to_i,
      exp: (Time.now + (72 * 60 * 60)).to_i
    }

    JWT.encode(payload, private_key, 'RS256')
  end

  def parse_form_params(body)
    return {} if body.nil? || body.empty?

    URI.decode_www_form(body).to_h
  rescue StandardError
    {}
  end

  # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
  def apply_state(params)
    state = params['state'] || 'active'
    days = (params['days'] || 30).to_i

    @current_state = case state
                     when 'active'
                       { status: 'active', cancel_at_period_end: false,
                         current_period_end: future_timestamp(days), simulate_error: false }
                     when 'trialing'
                       { status: 'trialing', cancel_at_period_end: false,
                         current_period_end: future_timestamp(days), simulate_error: false }
                     when 'past_due'
                       { status: 'past_due', cancel_at_period_end: false,
                         current_period_end: past_timestamp(5), simulate_error: false }
                     when 'canceling'
                       { status: 'active', cancel_at_period_end: true,
                         current_period_end: future_timestamp(days), simulate_error: false }
                     when 'inactive'
                       { status: 'inactive', cancel_at_period_end: false,
                         current_period_end: nil, simulate_error: false }
                     when 'network_error'
                       @current_state.merge(simulate_error: true)
                     else
                       @current_state
                     end

    puts "\n🔄 State changed to: #{state}"
  end
  # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity

  def future_timestamp(days)
    (Time.now + (days * 24 * 60 * 60)).to_i
  end

  def past_timestamp(days)
    (Time.now - (days * 24 * 60 * 60)).to_i
  end

  def send_response(client, status, content_type, body)
    status_text = { 200 => 'OK', 403 => 'Forbidden', 404 => 'Not Found' }[status] || 'OK'

    response = "HTTP/1.1 #{status} #{status_text}\r\n"
    response += "Content-Type: #{content_type}\r\n"
    response += "Content-Length: #{body.bytesize}\r\n"
    response += "Connection: close\r\n"
    response += "Access-Control-Allow-Origin: *\r\n"
    response += "\r\n"
    response += body

    client.print response
  end

  def handle_request(client)
    request = client.gets
    return unless request

    method, path = request.split
    content_length = read_headers(client)
    body = content_length.positive? ? client.read(content_length) : ''

    puts "#{method} #{path}"
    route_request(client, method, path, body)
  rescue StandardError => e
    puts "Error handling request: #{e.message}"
  end

  def read_headers(client)
    content_length = 0
    while (line = client.gets) && line != "\r\n"
      key, value = line.split(': ', 2)
      content_length = value.to_i if key.downcase == 'content-length'
    end
    content_length
  end

  def route_request(client, method, path, body)
    case [method, path.split('?').first]
    when ['GET', '/']
      send_response(client, 200, 'text/html', UI_HTML)
    when ['GET', '/status']
      send_response(client, 200, 'application/json', { current_state: @current_state }.to_json)
    when ['POST', '/set_state']
      apply_state(parse_form_params(body))
      send_response(client, 200, 'application/json', { status: 'ok', current_state: @current_state }.to_json)
    when ['POST', '/api/ping']
      handle_ping(client, body)
    else
      send_response(client, 404, 'text/plain', 'Not Found')
    end
  end

  def handle_ping(client, body)
    puts "\n📡 Received ping from Chatwoot"
    puts "   State: #{@current_state[:status]}"

    if @current_state[:simulate_error]
      puts '   Simulating network error (500)'
      send_response(client, 500, 'application/json', { error: 'Internal server error' }.to_json)
    elsif @current_state[:status] == 'inactive'
      send_response(client, 403, 'application/json', { error: 'No subscription' }.to_json)
    else
      data = JSON.parse(body) rescue {} # rubocop:disable Style/RescueModifier
      send_response(client, 200, 'application/json', { subscription_token: generate_token(data['installation_identifier']) }.to_json)
    end
  end

  def print_banner
    puts <<~BANNER

      ╔════════════════════════════════════════════════════════════╗
      ║           🎭 fazer.ai Hub Mock Server                      ║
      ╠════════════════════════════════════════════════════════════╣
      ║  Server running at http://localhost:#{PORT}                   ║
      ║                                                            ║
      ║  Set in .env: FAZER_AI_HUB_URL=http://localhost:#{PORT}       ║
      ║                                                            ║
      ║  Change state via:                                         ║
      ║  - Browser UI: http://localhost:#{PORT}                       ║
      ║  - curl: curl -X POST localhost:#{PORT}/set_state -d 'state=trialing&days=7'
      ║  ⚠️  After changing state:                                  ║
      ║      Go to Super Admin > Settings, click "Refresh" on      ║
      ║      fazer.ai subscription section.                        ║
      ╚════════════════════════════════════════════════════════════╝

    BANNER
  end

  def start_server
    server = TCPServer.new('0.0.0.0', PORT)

    trap('INT') do
      puts "\nShutting down..."
      server.close
      exit
    end

    loop do
      client = server.accept
      Thread.new(client) do |c|
        handle_request(c)
      ensure
        c.close
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength

# Only run the server when this file is executed directly
FazerAiHubMockServer.new.run if __FILE__ == $PROGRAM_NAME
