# Auditoria de Segurança — Tech-Auris/chatwoot

Data: 2026-05-09
Escopo principal: arquivos Auris-específicos divergindo do upstream `chatwoot/chatwoot` desde 2026-04-01, com amostragem dos pontos de upstream que tocam autenticação, criptografia e configuração.

## 1. Resumo executivo

| Severidade | Quantidade |
|---|---|
| CRÍTICO | 1 |
| ALTO | 5 |
| MÉDIO | 4 |
| BAIXO | 2 |
| INFO | 4 |

**Top 3 riscos:**

1. **Recursos globais sem `account_id`** (`FunnelStage`, `LossReason`) — qualquer admin ou manager de qualquer conta pode renomear, reordenar ou apagar essas tabelas, atingindo todas as contas da instalação ao mesmo tempo (ALTO, finding #1).
2. **Path traversal no `SwaggerController`** quando `ENABLE_SWAGGER_DOCS=true` em produção: `Rails.root.join('swagger', user_path)` aceita `params[:path]` absoluto, escapando do diretório (ALTO, finding #2). Em dev/test sempre habilitado.
3. **`JWT.decode ... false`** em `OauthCallbackController#users_data` — descodifica o id_token sem verificar assinatura. Mitigado pela origem server-to-server da requisição, mas qualquer regressão que repassasse um id_token vindo de input do usuário viraria takeover (CRÍTICO, finding #3 — upstream, mas presente no fork).

---

## 2. Findings detalhados

---

**[CRÍTICO] JWT decodificado sem verificação de assinatura**

- **Categoria**: Crypto / Autenticação
- **Arquivo**: [`app/controllers/oauth_callback_controller.rb:80`](app/controllers/oauth_callback_controller.rb#L80)
- **Trecho vulnerável**:
```ruby
def users_data
  decoded_token = JWT.decode parsed_body[:id_token], nil, false
  decoded_token[0]
end
```
- **Descrição**: O `false` final desliga a verificação de assinatura. Hoje o `parsed_body` vem do POST `https://oauth2.googleapis.com/token` (server-to-server, HTTPS, auth com client_secret), então o id_token é confiável **na origem**. Isso é o que mitiga o problema. Mas um único refactor que passe a aceitar `id_token` vindo de input do cliente, redirect param ou cabeçalho transforma isso num takeover trivial: o atacante forja um JWT com `email` e `email_verified=true` arbitrário, o controller cria/loga o usuário sem validar nada.
- **Impacto**: Account takeover universal se a fonte do `id_token` mudar.
- **Sugestão de correção**:
```ruby
def users_data
  jwks = oauth_provider_jwks  # cacheado, baixado de uma URL fixa (ex: https://www.googleapis.com/oauth2/v3/certs)
  decoded_token = JWT.decode(
    parsed_body[:id_token],
    nil,
    true,
    algorithms: ['RS256'],
    jwks: jwks,
    iss: 'https://accounts.google.com',
    verify_iss: true,
    aud: ENV.fetch('GOOGLE_OAUTH_CLIENT_ID'),
    verify_aud: true
  )
  decoded_token[0]
end
```
- **Referências**: CWE-345 (Insufficient Verification of Data Authenticity), OWASP Top 10 A07.

---

**[ALTO] FunnelStage e LossReason são globais e mutáveis por qualquer admin/manager**

- **Categoria**: IDOR cross-tenant / Autorização
- **Arquivos**:
  - [`app/policies/funnel_stage_policy.rb:11`](app/policies/funnel_stage_policy.rb#L11)
  - [`app/policies/loss_reason_policy.rb:11`](app/policies/loss_reason_policy.rb#L11)
  - [`app/controllers/api/v1/accounts/funnel_stages_controller.rb`](app/controllers/api/v1/accounts/funnel_stages_controller.rb)
  - [`app/controllers/api/v1/accounts/loss_reasons_controller.rb`](app/controllers/api/v1/accounts/loss_reasons_controller.rb)
  - [`db/schema.rb`](db/schema.rb) — tabelas `funnel_stages` e `loss_reasons` sem coluna `account_id`
- **Trecho vulnerável**:
```ruby
# funnel_stage_policy.rb
def update?
  @account_user.administrator? || @account_user.manager?
end

# funnel_stages_controller.rb
def update
  @funnel_stage.update!(permitted_params)  # FunnelStage é global, sem account_id
end
```
- **Descrição**: As migrations `20260503200000_make_funnel_stages_global.rb` e `20260504300000_create_loss_reasons_and_link_funnel_stage_changes.rb` removeram/nunca colocaram `account_id` nessas tabelas — funcionam como configuração de instalação. As policies só checam papel (`administrator? || manager?`), e os controllers carregam o registro por id sem filtrar por conta. Resultado: um manager de uma conta qualquer da instalação consegue, via API:
  - `PUT /api/v1/accounts/<qualquer>/funnel_stages/1` renomeando "Novo Contato" pra outra coisa em **todas as contas**.
  - `DELETE /api/v1/accounts/<qualquer>/funnel_stages/<id>` deletando uma raia que outra conta usa.
  - `POST /api/v1/accounts/<qualquer>/loss_reasons` poluindo o catálogo global.
- **Impacto**: Disrupção transversal entre contas — uma equipe pode quebrar o funil das outras. Em SaaS multi-tenant é uma quebra de isolamento. Em deploy single-tenant (uma conta por imagem) o impacto é só a conta dela mesma — então **dependa de como vocês operam**. Se for single-tenant Auris, é INFO; se algum dia houver mais de uma conta na mesma imagem, é ALTO/CRÍTICO.
- **Sugestão de correção**:
  - **Opção A (multi-tenant)**: adicionar `account_id` nas duas tabelas, escopar todos os queries (`current_account.funnel_stages`, `current_account.loss_reasons`), atualizar a policy pra verificar `record.account_id == @account_user.account_id`. Migration backfill copiando os atuais para cada conta.
  - **Opção B (decisão de design — global por instalação)**: mover esses recursos pro Super Admin (apenas super-admin lê e escreve), expor index pra admin/manager mas remover `create/update/destroy` do escopo da conta.
- **Referências**: CWE-639 (Authorization Bypass Through User-Controlled Key), OWASP A01 Broken Access Control.

---

**[ALTO] Path traversal em `SwaggerController` quando docs estão habilitadas**

- **Categoria**: Path Traversal / LFI
- **Arquivo**: [`app/controllers/swagger_controller.rb:5`](app/controllers/swagger_controller.rb#L5)
- **Trecho vulnerável**:
```ruby
def respond
  return head :not_found unless docs_enabled?

  render inline: Rails.root.join('swagger', derived_path).read
end

def derived_path
  params[:path] ||= 'index.html'
  path = Rack::Utils.clean_path_info(params[:path])
  ...
end
```
- **Descrição**: `Rack::Utils.clean_path_info` remove `..` mas **não** transforma path absoluto em relativo. `Pathname#join` com argumento absoluto descarta o prefixo (`Rails.root.join('swagger', '/etc/passwd')` retorna `Pathname('/etc/passwd')`). Então com `ENABLE_SWAGGER_DOCS=true` (e sempre em dev/test), `GET /swagger?path=/etc/passwd&format=` lê arquivos arbitrários do filesystem. Em produção é noop a menos que essa env esteja ligada.
- **Impacto**: Leitura de arquivos arbitrários — incluindo `config/master.key`, `.env`, snippets de credenciais. Combinado com `master.key` exposto, leva a decrypt de `credentials.yml.enc` → SECRET_KEY_BASE → cookie/session forging.
- **Sugestão de correção**:
```ruby
SWAGGER_ROOT = Rails.root.join('swagger').realpath.freeze

def respond
  return head :not_found unless docs_enabled?

  resolved = SWAGGER_ROOT.join(derived_path).expand_path
  return head :not_found unless resolved.to_s.start_with?(SWAGGER_ROOT.to_s) && resolved.file?

  render inline: resolved.read
end
```
- **Referências**: CWE-22 (Path Traversal), OWASP A01.

---

**[ALTO] CORS permissivo com exposição de tokens de autenticação**

- **Categoria**: Configuração / Auth
- **Arquivo**: [`config/initializers/cors.rb:6-22`](config/initializers/cors.rb#L6)
- **Trecho vulnerável**:
```ruby
allow do
  origins '*'
  resource '/public/api/*', headers: :any, methods: :any
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false)) || Rails.env.development?
    resource '*', headers: :any, methods: :any, expose: %w[access-token client uid expiry]
  end
end
```
- **Descrição**: Em modo "API only" ou em desenvolvimento, qualquer origem pode acessar todos os endpoints com cabeçalhos de auth expostos. Para deploys com FRONTEND_URL fixo, `origins '*'` deveria ser sempre o frontend conhecido. Se `CW_API_ONLY_SERVER=true` for usado em produção (ex: instância só-API consumida por outro app), abre porta pra CSRF cross-origin com tokens vazando.
- **Impacto**: Site malicioso visitado por agente logado consegue ler/escrever na API e capturar `access-token` exposto.
- **Sugestão de correção**: Trocar `origins '*'` (para o resource público) por allowlist de domínios; nunca expor `access-token` para origens não confiáveis.
- **Referências**: CWE-942 (Permissive CORS), OWASP A05.

---

**[ALTO] `valid_token?` de webhook usa `==` (timing attack)**

- **Categoria**: Crypto / Constant-time comparison
- **Arquivos**:
  - [`app/controllers/webhooks/whatsapp_controller.rb:35`](app/controllers/webhooks/whatsapp_controller.rb#L35)
  - [`app/controllers/webhooks/instagram_controller.rb:39`](app/controllers/webhooks/instagram_controller.rb#L39)
- **Trecho vulnerável**:
```ruby
def valid_token?(token)
  channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
  token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
end
```
- **Descrição**: Comparação de string com `==` retorna em tempo proporcional ao prefixo coincidente. Em rede pública, com latência baixa e milhares de tentativas, dá pra recuperar o token caractere a caractere. Outros adapters (Shopify, TikTok) já usam `ActiveSupport::SecurityUtils.secure_compare` corretamente.
- **Impacto**: Atacante adivinha o `webhook_verify_token` e injeta payloads forjados — spoofing de mensagens WhatsApp/Instagram.
- **Sugestão de correção**:
```ruby
def valid_token?(token)
  expected = channel&.provider_config&.[]('webhook_verify_token').to_s
  return false if expected.empty?
  ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
end
```
- **Referências**: CWE-208 (Observable Timing Discrepancy).

---

**[ALTO] CSP totalmente desabilitada**

- **Categoria**: Configuração / Hardening anti-XSS
- **Arquivo**: [`config/initializers/content_security_policy.rb`](config/initializers/content_security_policy.rb) (todo o arquivo está comentado)
- **Descrição**: Sem CSP, qualquer XSS refletido ou armazenado tem permissão pra rodar inline scripts, baixar payloads de qualquer origem e exfiltrar `localStorage`/cookies. Como o app renderiza muito conteúdo de usuário (mensagens, avatares, custom_attributes, summary, release notes via `v-html`), uma defesa em profundidade aqui é importante.
- **Impacto**: Agrava qualquer XSS pra exfiltração quase-trivial.
- **Sugestão de correção**:
```ruby
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.img_src :self, :data, :https
  policy.script_src :self
  policy.style_src :self, :unsafe_inline
  policy.connect_src :self, :https, :wss
  policy.object_src :none
  policy.frame_ancestors :self
end
Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
```
Liberar gradualmente conforme romper, em vez de manter desligado.
- **Referências**: OWASP CSP cheat sheet.

---

**[MÉDIO] `dismiss_release` aceita string sem limite de tamanho**

- **Categoria**: Input validation / DoS
- **Arquivo**: [`app/controllers/api/v1/profiles_controller.rb:50`](app/controllers/api/v1/profiles_controller.rb#L50)
- **Trecho vulnerável**:
```ruby
def dismiss_release
  tag = params[:tag].to_s
  return render_could_not_create_error('Missing release tag') if tag.blank?

  @user.update!(last_seen_release_tag: tag)
  head :ok
end
```
- **Descrição**: A coluna `users.last_seen_release_tag` é `:string` (≤255 em pg na prática, mas a migration não tem `limit:`). Sem validação no controller, um atacante pode mandar 200KB num único POST e bloatar o registro do usuário. O controller é autenticado, então é abuso por usuário válido — incômodo, não exploit clássico.
- **Impacto**: BAIXO em ataque externo, MÉDIO se um usuário malicioso quiser engordar a tabela `users`.
- **Sugestão de correção**: Validar contra a lista do `Release::CatalogService`:
```ruby
def dismiss_release
  tag = params[:tag].to_s
  return render_could_not_create_error('Missing release tag') if tag.blank?

  known_tags = ::Release::CatalogService.all.map { |r| r['tag'] }
  return render_could_not_create_error('Unknown release tag') unless known_tags.include?(tag)

  @user.update!(last_seen_release_tag: tag)
  head :ok
end
```
- **Referências**: CWE-1284 (Improper Validation of Specified Quantity in Input).

---

**[MÉDIO] Action Cable com proteção CSRF desativada**

- **Categoria**: Configuração
- **Arquivo**: [`config/initializers/cors.rb:35`](config/initializers/cors.rb#L35)
- **Trecho vulnerável**:
```ruby
Rails.application.config.action_cable.disable_request_forgery_protection = true
```
- **Descrição**: `disable_request_forgery_protection` faz com que qualquer Origin consiga abrir o websocket. Combinado com a auth via cookie do agente, um site malicioso visitado pelo agente abre uma conexão e se inscreve em conversas em tempo real (RoomChannel/ConversationChannel). O upstream Chatwoot fez essa decisão pra suportar widget público — mas vale restringir via `allowed_request_origins` ao FRONTEND_URL.
- **Impacto**: Vazamento em tempo real de mensagens privadas para sites que o agente visitar logado.
- **Sugestão de correção**:
```ruby
Rails.application.config.action_cable.disable_request_forgery_protection = false
Rails.application.config.action_cable.allowed_request_origins = [
  ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
  %r{\Ahttps://.*\.auris\.ia\.br\z}
]
```
- **Referências**: Rails Action Cable security.

---

**[MÉDIO] `force_ssl` opcional e devise password_length=6**

- **Categoria**: Configuração / Política de senha
- **Arquivos**:
  - [`config/environments/production.rb`](config/environments/production.rb) — `config.force_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', false))`
  - [`config/initializers/devise.rb:157`](config/initializers/devise.rb#L157) — `config.password_length = 6..128`
- **Descrição**: 
  - O `.env.example` e os deploys em produção que vimos têm `FORCE_SSL=false`. Sem isso, requisições HTTP nunca são redirecionadas para HTTPS, e cookies viajam em claro se houver fallback de cliente para HTTP.
  - 6 caracteres como mínimo de senha é fraco. Recomendação atual NIST/OWASP é mínimo 8-12, com checagem de senhas vazadas.
- **Impacto**: MÉDIO. Vetor MITM em redes públicas + brute force facilitado.
- **Sugestão de correção**: 
  - Definir `FORCE_SSL=true` em produção e remover o flag.
  - Subir `config.password_length = 12..128` e considerar plugar `pwned` gem pra checar contra haveibeenpwned.

---

**[MÉDIO] `SwaggerController` aceita também `params[:format]` sem sanitização robusta**

- **Categoria**: Path Traversal (variante)
- **Arquivo**: [`app/controllers/swagger_controller.rb:17`](app/controllers/swagger_controller.rb#L17)
- **Descrição**: `path << ".#{Rack::Utils.clean_path_info(params[:format])}"` — `clean_path_info` em uma extensão é menos estranho, mas se `params[:format]` vier como `"yml/../../config"`, o resultado vai ser anexado ao final. Mesma família do finding [ALTO] anterior; agrupa-se na correção.
- **Impacto**: Parte do mesmo vetor de path traversal.
- **Sugestão**: Whitelist de formatos (`%w[json yml html]`) antes de concatenar.

---

**[BAIXO] Active Record Encryption suporta dados não criptografados**

- **Categoria**: Crypto / Migração
- **Arquivo**: [`config/application.rb:82`](config/application.rb#L82) — `config.active_record.encryption.support_unencrypted_data = true`
- **Descrição**: Aceita ler campos legados em texto puro durante a migração. Se a migração já foi concluída em prod, vale desligar.
- **Sugestão**: Após confirmar 100% migrado, setar como `false`.

---

**[BAIXO] Devise `token_lifespan = 2.months` e `max_number_of_devices = 25`**

- **Arquivo**: [`config/initializers/devise_token_auth.rb`](config/initializers/devise_token_auth.rb)
- **Descrição**: Sessões muito longevas e muitos dispositivos simultâneos aumentam janela de uso de tokens roubados. Reduzir pra 7-30 dias e 5-10 devices é prática comum.

---

**[INFO] `MD5` em geração de hash do Gravatar e distribuição de jobs**

- **Arquivos**: `app/jobs/avatar/avatar_from_gravatar_job.rb`, `app/jobs/internal/trigger_daily_scheduled_items_job.rb`
- **Descrição**: MD5 usado para uso não-criptográfico (protocolo do Gravatar e particionamento de carga). Não é vulnerabilidade. Não mexer.

---

**[INFO] Custom attributes / additional_attributes / ui_settings permitem hash livre**

- **Arquivos**: vários controllers (conversations, contacts, profiles).
- **Descrição**: `params.permit(custom_attributes: {})` aceita qualquer chave aninhada. Como esses campos são `jsonb` e nunca interpolados em SQL nem renderizados sem escape, é aceitável. Vale documentar que JSON arbitrário pode entrar e qualquer feature futura que ler do JSON precisa tratar como input não confiável.

---

**[INFO] Dependências Gemfile.lock**

- Rails 7.1.5.2, Devise 4.9.4, Nokogiri 1.19.1, Rack 3.2.5, Puma 6.4.3 — todas em versões com fixes recentes. Sem CVEs abertos relevantes em fast scan.
- Recomendação: rodar `bundle audit check --update` no CI.

---

**[INFO] Sidekiq Web está atrás de `authenticated :super_admin`**

- **Arquivo**: [`config/routes.rb`](config/routes.rb)
- **Descrição**: Bem protegido. Manter.

---

## 3. Áreas que NÃO consegui auditar a fundo

- **Enterprise overlay** (`enterprise/`): inclui sobreposições de policies e listeners (Captain, billing). Foi sampleado mas não auditado linha a linha. Vale rodar uma passada focada se for ativada essa edição.
- **Frontend (Vue) end-to-end XSS**: vimos os pontos de `v-html` mais óbvios (release notes, message bubbles) e o uso de `formatMessage`. Uma auditoria de frontend completa exigiria também ProseMirror config, copilot, helpcenter, sandbox de iframe.
- **Sidekiq jobs**: foram olhados os mais novos; jobs de campanha, baileys, integrations não foram revisados a fundo — particularmente em torno de `Marshal.dump`/`Marshal.load` em fila Redis (que é segura por default no Rails 7, mas vale checar se há `serialize` custom).
- **Configuração de produção real**: `production.rb` foi olhado, mas o ambiente real depende dos `compose.yml` da máquina (vimos um). HSTS preload, `secure_headers`, e `Rack::Attack` (rate limiting) merecem revisão dedicada.
- **CSRF em `super_admin/`**: Devise + Administrate é um conjunto que herda proteção do Rails — passada superficial OK, mas sessões super-admin merecem teste manual: revogação após mudança de senha, escopo do MFA, replay do challenge ID.
- **Webhook Inbound do Z-API/Baileys**: o adapter desses providers tem URLs de mídia que viram `Down.download` — risco SSRF. Foi sinalizado em escopo geral mas não fui linha-a-linha.

## 4. Próximos passos recomendados

1. Decidir se `FunnelStage`/`LossReason` são globais por design (Super Admin) ou por conta. Implementar a opção escolhida.
2. Sanear `SwaggerController` (path traversal) e garantir que `ENABLE_SWAGGER_DOCS` está `false` em produção.
3. Trocar comparações de webhook pra `secure_compare`.
4. Habilitar CSP em modo report-only por algumas semanas, depois bloquear.
5. Setar `FORCE_SSL=true` em todas as imagens de produção e validar HSTS.
6. Limitar tamanho de `last_seen_release_tag` no `dismiss_release`.
7. Rodar `bundle audit` no CI.
