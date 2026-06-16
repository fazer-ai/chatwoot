---
name: sync-fork
description: Use this skill when syncing one of our forks with its upstream — either pulling chatwoot/chatwoot into fazer-ai/chatwoot, OR pulling fazer-ai/chatwoot `main` into fazer-ai/chatwoot-pro (`chatwoot-pro-main`). Covers per-file decision framework (KC/AI/CO/delete), recurring patterns (SaveBang, signature architecture, schema.rb regen, WhatsApp service, installation_config, Pro-only overrides), validation flow, and pre-commit/CI pitfalls specific to this repo. Trigger when the user asks to merge develop/main from chatwoot upstream, resolve merge conflicts on a merge branch, bump the fork to a new chatwoot version, or merge CE `main` into `chatwoot-pro-main`. **Never assume the sync direction — always confirm with the user which side is upstream and which is the receiving fork before doing anything.**
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Sync fork — (chatwoot → fazer-ai CE) and (fazer-ai CE → fazer-ai Pro)

> **Direction is never implicit.** Before reading any further, confirm with the user which sync flow this is: `chatwoot/chatwoot → fazer-ai/chatwoot` (CE merge) or `fazer-ai/chatwoot → fazer-ai/chatwoot-pro` (Pro merge). Both flows share most patterns but diverge on branch names, push targets, and which side is HEAD. Picking the wrong flow silently inverts the KC/AI decisions in every recurring pattern below — do not infer from context, ask.

The fazer-ai CE fork diverges from chatwoot upstream on real features (Baileys, Zapi, per-inbox signatures, scheduled messages, group conversations, internal chat). fazer-ai Pro further extends CE with Pro-only features (kanban, integrity reporting, protected subscription keys, configurable super-admin paywall URL, etc.). Every few releases we pull each level of upstream in to stay current. This skill captures the recurring patterns and footguns for **both** sync flows so the next merge doesn't rediscover them from scratch.

## Two merge flows this skill covers

### A) chatwoot/chatwoot → fazer-ai/chatwoot (CE merge)

Branch from our fork's `main`, merge `upstream/develop` (or a release tag like `chatwoot/develop`) into it via a `chore/merge-upstream-X.Y.Z` branch and PR.

- HEAD = fork (`main`), MERGE_HEAD = upstream.
- Same number of conflicts either way — git is symmetric.
- What differs: the `--first-parent` chain. Merging upstream into a fork-based branch keeps our main's first-parent history "our work", with upstream as a side merge. Easier to answer "what's ours" later with `git log --first-parent`.
- If the current in-progress merge already went the other direction, finish it as-is. Standardize on next merge.

### B) fazer-ai/chatwoot → fazer-ai/chatwoot-pro (Pro merge)

Switch to `chatwoot-pro-main`, pull it even with `chatwoot-pro/main`, then `git merge main --no-ff -m "Merge branch 'main' into chatwoot-pro-main"`. Repo history shows this is done directly on `chatwoot-pro-main` (no PR), then pushed to `chatwoot-pro/main` along with the new `vX.Y.Z-fazer-ai-pro.N` tag.

- HEAD = Pro (`chatwoot-pro-main`), MERGE_HEAD = CE (`main`).
- Pro is a strict superset of CE: every conflict is either "CE changed something we overrode" (usually KC/CO to preserve Pro behavior) or "CE added new code next to our additions" (usually CO).
- Recurring patterns below tagged **[Pro]** list files that conflict on almost every CE→Pro merge.

## How to use this skill (checklist)

When triggered on a merge, don't just read the file and wing it — walk the full flow:

1. Run the **Pre-flight** block.
2. For every conflicted file: apply the **Per-file decision framework**, cross-referencing the **Recurring patterns** subsection for that file when one exists.
3. Resolve and `git add` each file. Keep a running list of the KC/AI/CO/DEL decision per file (useful for the commit message and PR body).
4. Run the **Validation flow** end-to-end (it is mandatory, not optional). Do not commit if any step fails.
5. For Pro merges, recall that pushing to `chatwoot-pro/main` is directly followed by tagging `vX.Y.Z-fazer-ai-pro.N` and cutting a release — coordinate with the `release-notes` skill (and its `PRIVACY.md` companion) before writing the release body.

## Pre-flight

After `git merge upstream/develop` (CE) or `git merge main` (Pro), before touching anything:

```bash
# list conflicted files
git diff --name-only --diff-filter=U

# confirm direction — who is HEAD (ours) vs MERGE_HEAD (theirs)
cat .git/MERGE_HEAD
head -5 .git/MERGE_MSG
git log --oneline HEAD -3
git log --oneline MERGE_HEAD -3

# for Pro merges, confirm the branch and remote before doing anything destructive
git branch --show-current   # should be chatwoot-pro-main
git remote -v               # should show `chatwoot-pro` remote pointing at fazer-ai/chatwoot-pro
```

Terminology used in this skill:
- **HEAD / current / ours** = the branch you're sitting on (the one receiving the merge).
- **MERGE_HEAD / incoming / theirs** = the branch being merged in.

If you're on a fork-based branch pulling upstream in: `HEAD` = fork, `MERGE_HEAD` = upstream.
If you're on an upstream-based branch pulling fork in (the less-preferred direction): `HEAD` = upstream, `MERGE_HEAD` = fork.

Read carefully which side is which before labeling decisions.

## Per-file decision framework

For each conflicted file, pick one of:

| Code | Meaning |
|------|---------|
| **KC** | Keep current (HEAD) — drop the incoming side |
| **AI** | Accept incoming (MERGE_HEAD) — drop the HEAD side |
| **CO** | Combination — merge both sides manually |
| **DEL** | Accept deletion — `git rm` (modify/delete conflict where one side deleted) |

Process:

1. Read the conflict markers to see what each side does.
2. `git log --oneline HEAD -5 -- <path>` and `git log --oneline MERGE_HEAD -5 -- <path>` — understand WHY each side changed it.
3. For modify/delete: `git ls-files -u <path>` shows which stages are present (1=base, 2=ours, 3=theirs).
4. For complex hunks: `git show HEAD:<path>` and `git show MERGE_HEAD:<path>` to see each full file.
5. Decide KC/AI/CO/DEL based on intent, not just diff.

## Recurring patterns in this repo

### Style/SaveBang noise

Our fork has `Rails/SaveBang: Enabled: true` in `.rubocop.yml`. Upstream doesn't enforce it as strictly. Consequence: when upstream touches any line near a persistence call, we see a conflict where our side says `save!`/`update!`/`destroy!`/`create!` and theirs says the non-bang version.

The cop flags more than just `save`. Full list it tries to add `!` to: `save`, `update`, `update_attributes`, `destroy`, `create`, `create_or_find_by`, `find_or_create_by`, `find_or_initialize_by`, `first_or_create`, `first_or_initialize`. Any of these can appear in a conflict.

- Most are **trivial** style churn from our fork's rubocop autofix, no semantic change.
- **Never blindly accept the bang rewrite (or run `rubocop -A`) without evaluating each offense individually.** The cop doesn't check the receiver's class — it matches by method name alone. Non-ActiveRecord receivers (POROs, service objects with their own `save`/`update`/`destroy` method, third-party libraries like Stripe, Kredis, OpenStruct wrappers, CSV/IO objects with `update`, filesystem objects with `destroy`) will raise `NoMethodError` at runtime. Caught by CI if there's a spec, silently broken in prod if not.
- For each SaveBang offense, read the surrounding code: what class is the receiver? If it's an ActiveRecord model, the autocorrect is safe. If it's anything else, either add the receiver to `.rubocop.yml`'s `Rails/SaveBang.AllowedReceivers` list (currently Stripe::Subscription, Stripe::Customer, Stripe::Invoice) or add a targeted `rubocop:disable Rails/SaveBang` comment.
- Safe workflow: run `bundle exec rubocop <files>` (without `-A`) first to see the offenses listed, evaluate each individually, then apply `-A` only once you've confirmed every receiver is an ActiveRecord object. Always review the diff before committing.
- **Specs trap (4.14.2 merge):** receiver class is not enough — check INTENT. Upstream specs often call non-bang `update(...)` on purpose to assert validation failures right after (`expect(portal).not_to be_valid`). `rubocop -A` rewrites them to `update!` and the test now raises instead of failing validation. For those, keep `update` with an inline `# rubocop:disable Rails/SaveBang` (existing fork pattern in `spec/models/portal_spec.rb`).

### Signature architecture (PR #79)

We deliberately removed upstream's editor-side signature manipulation (`addSignature`, `removeSignature`, `toggleSignatureInEditor`, signature-in-draft logic) and moved signature application to **send-time** (`getMessagePayload`). This prevents signature duplication, persistence in drafts, and position-toggle bugs.

When upstream adds or tweaks any signature-related code in:
- `app/javascript/dashboard/components/widgets/WootWriter/Editor.vue`
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`
- `app/javascript/dashboard/routes/dashboard/settings/profile/MessageSignature.vue`

→ Usually **AI (accept incoming = our fork)**, preserving the send-time architecture. Upstream's "fixes" may be rebuilding exactly what we tore out.

One exception worth porting as follow-up (NOT during merge): upstream's inline-image sanitization (`stripInlineBase64Images` + `INLINE_IMAGE_WARNING` i18n key) is orthogonal to architecture and would be a nice safety net in our send-time code.

### WhatsApp incoming message service

`app/services/whatsapp/incoming_message_base_service.rb` is the other frequent conflict zone. Our fork has two-layer locking (source_id lock + contact phone lock) plus a contact-level re-check for slow networks. Upstream evolves its simpler dedup logic.

Decision: **CO (combination)**. Keep the fork's `acquire_message_processing_lock` + `with_contact_lock` + explicit `clear_message_source_id_from_redis` in `ensure`. Layer upstream's improvements in (e.g., the `@contact.blocked? && !outgoing_echo` check) at the equivalent point inside the contact lock.

Adjacent file that may need follow-up: `app/services/whatsapp/incoming_message_service_helpers.rb` typically auto-merges to our version. That's correct. If upstream's `Whatsapp::MessageDedupLock` class becomes orphaned after a merge, `git rm` it (and its spec).

**Known regression hiding here:** `acquire_message_processing_lock` in our fork checks `@processed_params.try(:[], :messages).blank?`, which skips `:message_echoes` payloads. Echoes from WhatsApp Cloud native-app sends were being silently dropped. Fixed in the 4.13.0 merge by changing to `messages_data.blank?` and picking `:to` vs `:from` for the contact phone based on `outgoing_echo`. Keep that fix on future merges.

**`unprocessable_message_type?` (4.14.2):** the list is now `%w[ephemeral request_welcome]`. `reaction` stays OUT (fork processes reactions, incl. `reaction_removal?`); `unsupported` stays OUT (upstream's `create_unsupported_message` persists a placeholder instead of dropping). If a future merge re-adds either to the list, that's upstream churn — keep them out.

### Voice notes meta keys: `is_voice_message` (canonical) vs `is_recorded_audio` (legacy)

The fork's dashboard voice-note pipeline was upstreamed by us as #14606 with the meta key renamed to `is_voice_message`. Decision made in the 4.14.2 merge: **converge the dashboard flow to upstream's key, keep the backend reading BOTH keys** — `is_recorded_audio` is still written by Baileys/Zapi PTT handlers, by the `transcode_audio` API pipeline, and exists on all historical messages.

- Frontend (`ReplyBox.vue`, `message.js`): only `isVoiceMessage`/`is_voice_message`. The fork's `removeRecordedAudio` re-record race fix (#91) and computed `hasRecordedAudio` are preserved on top of upstream's flow — keep them on future merges.
- Backend readers accept both: `Whatsapp::Providers::WhatsappCloudService#voice_message?` and `WhatsappBaileysService#voice_note_attachment?`. Baileys sets `content[:ptt] = true` only when voice (`compact` semantics — don't emit `ptt: false`, a spec pins this).
- `Messages::MessageBuilder` keeps the fork-only params (`is_recorded_audio`, `transcode_audio`, `attachments_metadata`) for external API consumers, plus upstream's `is_voice_message`/`tag_voice_message`. Do NOT assign `attachment.meta = nil` — upstream specs expect the jsonb default `{}` to survive (assign only when `metadata.present?`).

### Opus normalization lives in the model, not the provider service (PR #223)

Fork architecture: `Attachment#normalize_opus_blob_content_type!` (lazy, called from `download_url`, uses `update_column`) + `config/initializers/active_storage_opus_fix.rb` (normalizes at identification time). Upstream still carries a service-level `normalize_opus_content_type` in `whatsapp_cloud_service.rb` whose `blob.update` **fails silently on validation** — that's why #223 moved to `update_column`. On every merge: **delete the service-level method + its call** if upstream re-introduces it (it did in 4.14.2).

### Portal custom HTML injection (custom_head_html / custom_body_html)

Upstream 4.14.x extracted the public portal layout into shared partials `app/views/layouts/_portal_head.html.erb` and `_portal_scripts.html.erb`, used by both `portal.html.erb` and the new `portal.html+documentation.erb` variant. The fork's `custom_head_html`/`custom_body_html` injection lives at the END of those partials (guarded by `!@is_plain_layout_enabled`). If upstream rewrites the layouts again, re-attach the injection to whatever shared partial both variants render. Also: `show_author` must stay in `Portal::CONFIG_JSON_KEYS`, and the fork's `merged_portal_params` controller helper is GONE — upstream's model-level `normalize_config` (merges `persisted_config`) replaced it.

### db/schema.rb

Always conflicts because both sides have different migration versions. Resolution is mechanical but has traps:

1. Resolve the version-number conflict first so Ruby can parse the file (`ActiveRecord::Schema[7.1].define(version: ...)`). Pick the later timestamp.
2. Resolve every other Ruby conflict file (`installation_config.rb`, any model conflicts) so Rails can boot.
3. `bundle exec rails db:migrate` to apply pending migrations.
4. `bundle exec rails db:schema:dump` to regenerate.

**Traps to remember:**

- **Local dev DB may have tables from other branches** (kanban, features in progress). After `db:schema:dump`, diff against `git show HEAD:db/schema.rb` and `git show MERGE_HEAD:db/schema.rb` to find extras. Manually delete stray `create_table` blocks + any foreign-key references + column references in shared tables (`conversations.kanban_task_id`, etc.).

- **Custom SQL functions aren't dumpable.** `db:schema:dump` strips our `execute <<~SQL CREATE OR REPLACE FUNCTION f_unaccent(text)` block. Automated re-injection is wired via the `Rakefile` + `lib/tasks/internal_chat_search.rake` (`db:internal_chat:inject_schema_functions` runs as an `enhance` hook after `db:schema:dump`). If you see the block missing after a dump, the hook didn't run — check the Rakefile wiring and the task for a warning line like `Could not find insertion point ...`. The function itself is created by migration `20260410170003_add_unaccent_search_to_internal_chat.rb`.

- **Schema version may be stamped with a migration from another branch.** `db:schema:dump` uses `MAX(schema_migrations.version)`. If the dev DB has a kanban/other-branch migration with a higher timestamp, that version ends up in `schema.rb`. Manually set the version to the highest timestamp among migrations *present in this merge's `db/migrate/`*.

- **Quick integrity diff** (in Python — sed-free): parse HEAD's schema + MERGE_HEAD's schema + merged schema, compare column/index sets per table. Any table with columns outside HEAD∪MERGE_HEAD is a stray from another branch.

### annotate_rb vs auto_annotate_models

Upstream migrated `.annotaterb.yml` + `lib/tasks/annotate_rb.rake` and deleted the old custom `lib/tasks/auto_annotate_models.rake`. Our fork did a similar migration earlier with different config style.

- `.annotaterb.yml`: **KC** for CE merge (upstream's format is more complete, symbol-key style).
- `lib/tasks/auto_annotate_models.rake`: **DEL** (`git rm`). Replacement is `lib/tasks/annotate_rb.rake` from upstream.

For **CE→Pro merges**, `.annotaterb.yml` is **CO**: adopt CE's newer format but keep the Pro-only `fazer_ai/app/models` entry in `model_dir`. Pro scans fazer-ai-specific models living under `fazer_ai/app/models`; dropping that path silently stops annotation for those models.

### Pro-only UI overrides

Pro deliberately patched a few CE components to widen access or make URLs configurable. On every CE→Pro merge CE's changes near these points re-conflict:

- **`app/javascript/dashboard/routes/dashboard/settings/components/BasePaywallModal.vue`** — Pro removed CE's `!isOnChatwootCloud` guard (so super admins see the CTA on cloud too) and added a `superAdminUrl` prop with a default so Pro instances can point to their own admin panel. → **KC**: keep Pro's `v-else-if="isSuperAdmin"` + `:href="superAdminUrl"`.

### Pro automation composables

Pro extended the automation composables to feed conditions/actions state into dropdown builders (used by kanban and other Pro-only conditions). When CE upstream touches the same functions, the signatures diverge.

- **`app/javascript/dashboard/composables/useAutomationValues.js`** — Pro signature is `getActionDropdownValues(type, conditions = [], actions = [])`. CE sometimes changes the signature (4.13.0 added `last_responding_agent` injection in the body). → **CO**: keep Pro's signature, layer CE's body changes in. If CE introduced a local variable like `agentsList`, let the returned `agents:` key read from it — pass Pro's `conditions` and `actions` through unchanged.

- **`app/javascript/dashboard/composables/useEditableAutomation.js`** — Pro recomputes `getConditionDropdownValues(condition.attribute_key, automation.conditions)` inside the filter (conditions affect dropdown content). CE reuses the pre-computed `dropdownValues` without conditions. → **KC**: keep Pro's recompute-with-conditions pattern; dropping it silently breaks kanban-related automation dropdowns.

### InstallationConfig serialize

Upstream simplified to `serialize :serialized_value, coder: YAML, type: ActiveSupport::HashWithIndifferentAccess, default: {}.with_indifferent_access`. Our fork had a custom `SerializedValueCoder` handling both YAML strings and native jsonb hashes.

Test before choosing: create a legacy `InstallationConfig` where `serialized_value` is a YAML string inside the jsonb column, then confirm upstream's simpler version can still load it. If it works (it did in 4.13.0 merge with all 3 legacy formats: tagged YAML, symbol-key YAML, native hash), go **KC**. Otherwise keep the custom coder.

Pro adds `PROTECTED_SUBSCRIPTION_KEYS` constant + `protected_subscription_key_check` validator on top of CE's version. On a CE→Pro merge the serialize block and the PROTECTED_SUBSCRIPTION_KEYS block may conflict as one hunk.

- **[Pro] CE→Pro merge:** **CO** — accept CE's simplified serialize (already validated against legacy data in 4.13.0), keep Pro's `PROTECTED_SUBSCRIPTION_KEYS`, `protected_subscription_key_check` validate, and related tests. Verify with `bundle exec rspec spec/models/installation_config_spec.rb` — both the `describe 'new record defaults'` (CE) and `describe 'protected fazer.ai config keys'` (Pro) blocks must stay.

### i18n files

`config/locales/en.yml` / `pt_BR.yml` and `app/javascript/dashboard/i18n/locale/en/settings.json` / `pt_BR/settings.json` conflict because both sides add keys. Almost always **CO**: merge both key sets under the right parent.

When upstream only adds `en.yml` keys and not `pt_BR.yml`, match upstream's scope — do not invent pt_BR translations as part of the merge. Those come in as community PRs or a separate translation pass.

### New features from both sides

Controllers (`inboxes_controller`, `conversations_controller`), policies, routes, store modules, automation_rule action whitelist, spec describe-blocks — when both sides added net-new methods/endpoints/actions, the resolution is always **CO**. Keep both additions ordered sensibly.

## Validation flow

**This flow is mandatory — do not commit the merge without running it.** Reading the skill is not enough; past merges have reached commit/push with silently broken state (class autoload issues, missing f_unaccent function, stray tables in schema.rb, rubocop offenses in upstream-only files) because validation steps were skipped.

After staging all resolved files and before commit:

```bash
# 1. parse sanity (catches stray conflict markers / bad YAML / bad Ruby)
ruby -c app/models/installation_config.rb
ruby -c db/schema.rb
grep -l '<<<<<<<\|=======\|>>>>>>>' $(git diff --name-only --cached) || echo "no leftover markers"

# 2. rails boots (catches broken autoload, bad requires, missing constants)
bundle exec rails runner 'puts "ok"'

# 3. migrations all apply (catches missing f_unaccent, bad schema.rb, stray tables)
bundle exec rails db:migrate

# 4. specs for each changed area at minimum (scale up for CE merges, keep targeted for Pro merges)
bundle exec rspec spec/models spec/policies
bundle exec rspec spec/services/whatsapp  # only when WA service touched
bundle exec rspec spec/controllers/api/v1/accounts/inboxes_controller_spec.rb \
                  spec/controllers/api/v1/accounts/conversations_controller_spec.rb \
                  spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb

# 5. targeted specs for files we actually resolved (always run)
bundle exec rspec spec/models/installation_config_spec.rb  # both CE and Pro describe blocks must pass
# Pro-only specs live under fazer_ai/spec/, NOT spec/lib/fazer_ai/ — rspec silently returns 0 examples on the wrong path
bundle exec rspec fazer_ai/spec/lib/fazer_ai/integrity_report_spec.rb fazer_ai/spec/lib/fazer_ai_hub_spec.rb  # run when Pro-specific Ruby touched

# 6. rubocop project-wide (Husky only lints staged diff; upstream files with offenses slip past)
bundle exec rubocop --parallel

# 7. smoke: exercise serialize/legacy-data paths and anything else the merge touched
bundle exec rails runner 'InstallationConfig.find_each { |c| c.value }; puts "legacy configs load ok"'

# 8. targeted JS specs for changed composables / Vue components
# `pnpm test` wraps vitest with `--no-cache` which OOMs the runner on WSL. Use vitest directly
# with a bigger Node heap when testing composables / big dashboards:
NODE_OPTIONS="--max-old-space-size=4096" npx vitest run \
  app/javascript/dashboard/composables/spec/useEditableAutomation.spec.js \
  app/javascript/dashboard/composables/spec/useAutomation.spec.js \
  --no-coverage --reporter=verbose
```

Keep the output around until after push — if CI fails, being able to compare local vs CI run saves a round trip.

## Pre-commit pitfalls

1. **Husky rubocop check only inspects files with staged diff.** Upstream files merged as-is don't appear in the diff, so their offenses slip past the hook and blow up in CI. Before commit:
   ```bash
   bundle exec rubocop --parallel
   ```
   Run the full thing. Fix anything that comes up (most are `Rails/SaveBang` in upstream migrations/specs — safe to `rubocop -A` after receiver check).

2. **Frontend lint error vs warning.** `pnpm-lint-staged` eslint runs with `--max-warnings=0` in some configs; a warning appears as an error in the hook. Check the actual error line in the hook output, not the warning count.

3. **Missing imports after removing conflict hunks.** When resolving AI (accept incoming) conflicts in JS/Vue files, you can accidentally delete imports you still need. Example from 4.13.0: `replaceVariablesInMessage` in `ReplyBox.vue` — the `replaceText` method came in from main but its import was above the conflict. After keeping `replaceText`, add the import.

4. **Duplicate `defineExpose` / `setup()` returns.** Same category: when combining both sides of a Vue component, watch for duplicate `defineExpose({ ... })` calls or duplicate keys in the `setup()` return object. Consolidate.

## What this skill deliberately does NOT cover

- CI flakiness from shard redistribution (pre-existing test pollution involving `perform_enqueued_jobs` in `before_all`, test-prof `let_it_be`, and rspec-mocks interaction). Track separately.
- Frontend build pipeline issues unrelated to the merge.
- Upstream feature rollouts that need product decisions (e.g., adopting a new captain model in our UI).
