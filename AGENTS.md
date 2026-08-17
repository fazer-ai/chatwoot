# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rvm`
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- New features must include specs covering the main flows (happy path + critical edge cases). Bugfixes should add a regression spec when the fix is non-trivial. Skip specs only for purely cosmetic changes (CSS tweaks, copy adjustments, log message edits) or when the user explicitly asks to skip.
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Worktree Workflow

Use a separate git worktree + branch per task so multiple instances run in parallel, fully isolated.

A new worktree only materializes **versioned** files — `git worktree add` does NOT copy the gitignored, per-worktree setup: `.env`, `.env.test`, `Procfile.worktree`, `.bundle/config`, and `CLAUDE.local.md`. Generate these per worktree with non-colliding values:

- **Ports**: distinct Rails (`PORT`) and Vite (`VITE_RUBY_PORT`).
- **Postgres**: a dedicated `POSTGRES_DATABASE`, separate for dev and test — `.env.test` overrides it so specs never touch the dev DB (dotenv-rails loads `.env.test` before `.env` under `RAILS_ENV=test`).
- **Redis**: a distinct logical DB index (dev and test) via `REDIS_URL`.
- **Hostname**: a distinct `*.localhost` host in `FRONTEND_URL` (macOS resolves `*.localhost` natively) so session cookies don't clash between worktrees.
- **Overmind**: its own `OVERMIND_SOCKET`; start with `overmind start -f Procfile.worktree`.

Automate this with your worktree tool's create hook (e.g. worktrunk's `pre-start`): generate the local files from a shared master `.env`, derive the values above deterministically from the branch name, run `bundle install && pnpm install`, then create the DBs (`rails db:prepare` for dev; `RAILS_ENV=test rails db:create db:schema:load` for test). Keep DB setup non-fatal so a broken seed doesn't abort worktree creation. The actual per-worktree URL/port/DB/Redis values land in that worktree's `CLAUDE.local.md`.

## Release Notes

- Every GitHub release cut from this repo must include the bilingual `user-notes` blocks (pt-BR + en) in the release body, written for non-technical end users.
- Before running `gh release create`, `gh release edit`, the `release` skill from `fazer-ai-tools`, or any flow that touches a release body (including retroactive backfills), invoke the `release-user-notes` skill at `.claude/skills/release-user-notes/SKILL.md` to draft and validate the blocks.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## Git Remotes & PRs

This repo is a fork of `chatwoot/chatwoot`. Remotes and their roles:

- **origin** → `fazer-ai/chatwoot` (our CE fork). Feature/fix PRs from `main` target this repo.
- **chatwoot-pro** → `fazer-ai/chatwoot-pro` (Pro fork). `chatwoot-pro-main` is merged directly (no PR) and carries the `vX.Y.Z-fazer-ai-pro.N` tags/releases.
- **upstream** → `chatwoot/chatwoot` (Chatwoot OSS). Read-only / sync only (merge `develop` via the `sync-fork` skill). **Never open a PR against upstream.**

⚠️ **`gh` fork gotcha:** because `origin` is a fork of `chatwoot/chatwoot`, `gh` resolves the PR base repo to the **parent (upstream)** when no default is set — so `gh pr create` silently opens the PR on `chatwoot/chatwoot`. Pin the base repo once per clone:

```sh
gh repo set-default fazer-ai/chatwoot   # writes remote.origin.gh-resolved=base
```

When unsure, be explicit: `gh pr create --repo fazer-ai/chatwoot` (for Pro PRs, `--repo fazer-ai/chatwoot-pro`).

### Merge strategy

- Default for every PR: `gh pr merge <n> --squash --admin`.
- **Exception — upstream sync PRs (`chore/merge-upstream-X.Y.Z`): merge with `--merge`, never `--squash`.** A squash drops the merge commit's second parent, so the upstream tag stops being an ancestor of `main`: GitHub reports `main` as permanently "N commits behind chatwoot:develop" (the count only grows), and the next sync bases on a stale tag and replays a whole version's diff as conflicts. After merging a sync PR, `git rev-list --count main..vX.Y.Z` must be 0 — when it isn't, see the `sync-fork` skill's **Repairing a squashed sync** recipe.

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - Update `en.yml`/`en.json` and `pt_BR.yml`/`pt_BR.json`
  - Other languages are handled by the community
  - Backend i18n → `.yml`, Frontend i18n → `.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

## Account-level toggles: do NOT extend `config/features.yml`

- Since upstream 4.16.0, account feature flags are multi-column: `Featurable::FEATURE_FLAG_COLUMNS` maps `config/features.yml` entries to `accounts.feature_flags` (default) or `accounts.feature_flags_ext_1` via each entry's `column:` key, with a hard cap of 63 flags per bigint column enforced at boot (`validate_feature_count!` raises). The default column is FULL (63/63) — any new upstream-style flag MUST set `column: feature_flags_ext_1` and be appended at the end.
- Bit positions are persisted per column: never reorder or remove existing entries, and never change an existing feature's `column` after release.
- `chatwoot-pro-main` inserts `kanban` and `internal_chat_pro` mid-list in the DEFAULT column. With the 63-per-column boot validation, the next CE→Pro merge will raise `ArgumentError` at boot until Pro's extra flags move to `feature_flags_ext_1` — and moving them changes their persisted bit positions on Pro installs, so that migration must remap existing account values.
- Local DB pitfall: bit positions differ between `main` and `chatwoot-pro-main` because of the kanban/internal_chat_pro insertion. The same bit set on one branch maps to a different feature on the other. Use separate dev DBs per branch or reset `feature_flags` when switching.

For NEW account-level toggles, prefer the `settings` jsonb column instead of `feature_flags`:

1. Declare a `store_accessor :settings, :your_toggle` in `app/models/account.rb` and override the writer to cast (`super(ActiveModel::Type::Boolean.new.cast(value))` for booleans) so JSON schema validation accepts the value.
2. Add the key to `SETTINGS_PARAMS_SCHEMA` in `app/models/concerns/account_settings_schema.rb`.
3. Register it as a `Field::Boolean` (or appropriate field) in `app/dashboards/account_dashboard.rb` (`ATTRIBUTE_TYPES`, `FORM_ATTRIBUTES`, `SHOW_PAGE_ATTRIBUTES`).
4. The frontend reads it from `account.settings.your_toggle` (already serialized via `app/views/api/v1/models/_account.json.jbuilder` as `json.settings resource.settings`).

This keeps toggles keyed by name (immune to bit-position drift between branches) and unbounded by the bigint width.
