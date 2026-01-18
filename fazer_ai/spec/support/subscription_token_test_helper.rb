# frozen_string_literal: true

module FazerAi::SubscriptionTokenTestHelper
  TEST_PRIVATE_KEY = <<~PEM
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

  TEST_PUBLIC_KEY = <<~PEM
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr9ICjCbXqQxIS7jmSaeG
    5ifkpEzM0dc9/YCmTW/wVClVDpgRCUpNgCeXG45PX8/LDa1JLgoyeBjCdaHMgLpb
    1I9ssWCMKBXOfHd9HsswCosWacbwiM7ZiLhByAh1KgUAYV5KTbGgJM9Bf/JPv6L4
    b08FRb67OO4gdQxRQljY5ibj8MfF1NeB9c6PKWa41CAhkVGr+bktoL8lfQ357a2F
    N8o2wr/TzlH/SvTK7GZp61ZBJQ9hsKuxvQ0IBib2kem2aHEvRtMZ2AIrTCkmspAJ
    ReAtw7sC/gVAheqw0qGcYBQsF4gK06L60oj8NAra1diA+WPlCE3wD5365iaZLmIf
    TQIDAQAB
    -----END PUBLIC KEY-----
  PEM

  def self.included(base)
    base.before do
      stub_test_public_key
    end
  end

  def stub_test_public_key
    test_key = OpenSSL::PKey::RSA.new(TEST_PUBLIC_KEY)
    allow(FazerAi::SubscriptionToken).to receive(:public_key).and_return(test_key)
  end

  def generate_test_subscription_token(
    status: 'active',
    installation_identifier: nil,
    instance_type: 'chatwoot',
    features: {}
  )
    installation_identifier ||= ChatwootHub.installation_identifier

    payload = {
      status: status,
      instance_type: instance_type,
      installation_identifier: installation_identifier,
      features: features
    }

    FazerAi::SubscriptionToken.generate(payload, TEST_PRIVATE_KEY)
  end

  def generate_hub_response_with_token(
    status: 'active',
    instance_type: 'chatwoot',
    features: { 'kanban' => { 'account_limit' => 5 } },
    version: '4.0.0'
  )
    token = generate_test_subscription_token(
      status: status,
      instance_type: instance_type,
      features: features
    )

    {
      'version' => version,
      'subscription_token' => token
    }
  end
end
