#!/bin/sh

set -x

# Hold the worker until the schema it is about to load is the current one.
#
# ActiveRecord reads a model's columns once and keeps them for the life of the process, so
# a worker that loads Conversation one migration behind carries that schema until it is
# restarted. Every write that needs the new column then raises NoMethodError, and only the
# paths that CREATE a record reach it: an inbox with existing threads keeps receiving, and
# the loss surfaces as dead jobs nobody is watching. Measured on a real deploy: 672 history
# import jobs and 12 live messages dropped over eighty minutes, with nothing on the inbox
# saying so.
#
# docker-compose.coolify.yaml also states this as `depends_on: condition: service_healthy`,
# and that is not enough on its own. Coolify strips `depends_on` from the compose it
# actually deploys (verified on the stack that hit the bug), and docker does not re-apply
# the ordering when a single container is restarted later. The gate has to live somewhere
# it cannot be dropped, which is here.
#
# The Rails container owns the migrations; this one only waits for them. A worker that
# comes up alone against a database nobody is migrating waits forever, on purpose: the
# healthcheck greps for a sidekiq process, so the wait shows up as an unhealthy container
# instead of as a worker quietly writing against the wrong schema.

# Let DATABASE_URL env take presedence over individual connection params.
$(docker/entrypoints/helpers/pg_database_url.rb)
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

echo "Waiting for postgres to become ready...."

until $PG_READY
do
  sleep 2;
done

echo "Database ready to accept connections."

echo "Waiting for the schema to be current...."

until bundle exec rake db:abort_if_pending_migrations
do
  sleep 5;
done

echo "Schema is current. Starting the worker."

# Execute the main process of the container
exec "$@"
