# fazer_ai_ee

The fork's changes to Enterprise behavior. `enterprise/` and `spec/enterprise/` stay byte-identical to the upstream release in `VERSION_CW`, which keeps upstream merges free of conflicts there; everything the fork adds or changes on top of them lives here.

This directory only means something on top of `enterprise/`. It loads only when `enterprise/` is present (`config/application.rb`, `ChatwootApp.fazer_ai_ee?`). The CE spec workflows strip it together with `enterprise/`; the published images keep it and get `enterprise/` at boot (see below).

## In the image

No published image carries `enterprise/`. `docker/Dockerfile` downloads the official tree for `VERSION_CW` in its `enterprise-lock` stage, pins the hash of that tree in `/app/.enterprise_lock`, builds the assets with it in place (Tailwind reads its views) and drops it, leaving `/app/enterprise` as a link to `tmp/cw-enterprise`, the container's own activation. While that is missing the link dangles and `ChatwootApp.enterprise?` is false, so every container starts as Community. A build context whose `enterprise/` differs from the official tree fails there.

At boot, `docker/entrypoints/helpers/enterprise.sh ensure` runs from every entrypoint (`docker-entrypoint.sh`, `rails.sh`, `sidekiq.sh`) before anything boots Rails. With `CW_EDITION=ee` it points `tmp/cw-enterprise` at the entry for this version and hash in `storage/.cw-enterprise`, which the web and worker containers share. An intact entry is used without a lock and without writing to the volume; otherwise the tree is downloaded from the tag, checked against the pin and published by an atomic rename, under an exclusive lock on `storage/.cw-enterprise/.lock`. Entries are never changed or removed by a container switching Enterprise off. Without `CW_EDITION=ee` it removes `tmp/cw-enterprise`, so the decision stays inside each container. It writes only to `tmp/` and, for a download, to `storage/`, so the rest of `/app` can be read-only. Any failure stops the container with a message; `CW_EDITION=ce` boots without Enterprise on purpose. `spec/docker/enterprise_helper_spec.rb` covers each path.

## How a change lands here

- **New Enterprise-only code** (a controller, a job, a service): put it under `fazer_ai_ee/app/<type>/` with its normal constant name, the way it would sit under `enterprise/app/`. Zeitwerk loads it from here.
- **A change to a CE class that Enterprise extends** (the class calls `prepend_mod_with`): write `FazerAiEe::<same name>` under `fazer_ai_ee/app/<type>/fazer_ai_ee/`. `ChatwootApp.extensions` lists `fazer_ai_ee` right after `enterprise`, so the hook prepends it over the Enterprise module.
- **A change to an Enterprise-only class** (no hook): write `FazerAiEe::<same name>` the same way and add the class to `config/initializers/prepend_overrides.rb`.
- **A view**: copy it to `fazer_ai_ee/app/views/` at the same path. That view path comes before `enterprise/app/views`.
- **A timeout or retry policy on an Enterprise HTTP call**: list the method in `fazer_ai_ee/lib/fazer_ai_ee/request_ceilings.rb`. Inside a listed method HTTParty gets the ceiling as default options (the call's own options still win); outside, nothing changes. `spec/lib/request_ceilings_spec.rb` fails when `enterprise/` has an HTTParty call outside every listed method.
- **Config Enterprise reads from a fixed path** (`enterprise/config/*.yml`): keep the fork's additions in `fazer_ai_ee/config/` and merge them in from the service that reads the file, as `FazerAiEe::Internal::ReconcilePlanConfigService` does.
- **Specs**: under `fazer_ai_ee/spec/`, mirroring the `spec/` layout. Run them with `bundle exec rspec fazer_ai_ee/spec`. An upstream example under `spec/enterprise` that cannot pass on the fork is skipped by name in `spec/support/superseded_upstream_examples.rb`, next to the spec here that replaces it.

Prefer overriding with `super` around upstream's method. When the change sits in the middle of a method and the whole method has to be copied, add its fingerprint to `spec/upstream_overrides_spec.rb`, which fails when upstream changes the original, so the copy is re-read on the next merge instead of silently shadowing it. The same spec checks that every override is in front of its target and that each `super` still reaches an upstream method.

## Guards

- `bin/validate_enterprise_parity` compares `enterprise/` and `spec/enterprise/` with the upstream tag. CI runs it (`.github/workflows/enterprise_parity.yml`) and the pre-commit hook runs it on the index, except while a merge is in progress.
- `.claude/settings.json` denies agent edits under `enterprise/` and points here.
- RuboCop and annotate skip `enterprise/` and `spec/enterprise/`, so nothing reformats them.

## Merging an upstream release

Take upstream's side for every conflict under `enterprise/` and `spec/enterprise/` (`git checkout --theirs`), then run `bundle exec rspec fazer_ai_ee/spec`. A failing fingerprint means an override copies a method upstream changed: port upstream's change into the copy, then update the fingerprint.
