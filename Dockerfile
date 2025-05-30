FROM ghcr.io/fazer-ai/chatwoot:latest

WORKDIR /app

ENV NODE_ENV=production \
    RAILS_ENV=production \
    INSTALLATION_ENV=docker \
    DEFAULT_LOCALE=pt_BR \
    INTERNAL_HOST_URL=http://rails:3000 \
    POSTGRES_PORT=5432 \
    POSTGRES_DATABASE=chatwoot_production \
    REDIS_URL=redis://redis:6379 \
    BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL=true

EXPOSE 3000

CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
