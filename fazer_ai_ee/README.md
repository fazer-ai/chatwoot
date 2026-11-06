# fazer_ai_ee

The fork's changes to Enterprise behavior. `enterprise/` and `spec/enterprise/` stay byte-identical to the upstream release in `VERSION_CW`, which keeps upstream merges free of conflicts there; everything the fork adds or changes on top of them lives here.

This directory only means something on top of `enterprise/`. It loads only when `enterprise/` is present (`config/application.rb`, `ChatwootApp.fazer_ai_ee?`), and the CE workflows strip it together with `enterprise/`.

## How a change lands here

- **New Enterprise-only code** (a controller, a job, a service): put it under `fazer_ai_ee/app/<type>/` with its normal constant name, the way it would sit under `enterprise/app/`. Zeitwerk loads it from here.
- **A change to a CE class that Enterprise extends** (the class calls `prepend_mod_with`): write `FazerAiEe::<same name>` under `fazer_ai_ee/app/<type>/fazer_ai_ee/`. `ChatwootApp.extensions` lists `fazer_ai_ee` right after `enterprise`, so the hook prepends it over the Enterprise module.
- **A change to an Enterprise-only class** (no hook): write `FazerAiEe::<same name>` the same way and add the class to `config/initializers/prepend_overrides.rb`.
- **A view**: copy it to `fazer_ai_ee/app/views/` at the same path. That view path comes before `enterprise/app/views`.
- **Config Enterprise reads from a fixed path** (`enterprise/config/*.yml`): keep the fork's additions in `fazer_ai_ee/config/` and merge them in from the service that reads the file, as `FazerAiEe::Internal::ReconcilePlanConfigService` does.
- **Specs**: under `fazer_ai_ee/spec/`, mirroring the `spec/` layout. Run them with `bundle exec rspec fazer_ai_ee/spec`. An upstream example under `spec/enterprise` that cannot pass on the fork is skipped by name in `spec/support/superseded_upstream_examples.rb`, next to the spec here that replaces it.

Prefer overriding with `super` around upstream's method. When the change sits in the middle of a method and the whole method has to be copied, add its fingerprint to `spec/upstream_overrides_spec.rb`, which fails when upstream changes the original, so the copy is re-read on the next merge instead of silently shadowing it. The same spec checks that every override is in front of its target and that each `super` still reaches an upstream method.

## Guards

- `bin/validate_enterprise_parity` compares `enterprise/` and `spec/enterprise/` with the upstream tag. CI runs it (`.github/workflows/enterprise_parity.yml`) and the pre-commit hook runs it on the index, except while a merge is in progress.
- `.claude/settings.json` denies agent edits under `enterprise/` and points here.
- RuboCop and annotate skip `enterprise/` and `spec/enterprise/`, so nothing reformats them.

## Merging an upstream release

Take upstream's side for every conflict under `enterprise/` and `spec/enterprise/` (`git checkout --theirs`), then run `bundle exec rspec fazer_ai_ee/spec`. A failing fingerprint means an override copies a method upstream changed: port upstream's change into the copy, then update the fingerprint.
