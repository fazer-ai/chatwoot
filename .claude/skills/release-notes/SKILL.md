---
name: release-notes
description: Use this skill whenever you are about to cut, edit, or backfill a GitHub release for fazer-ai/chatwoot. Generates the bilingual user-notes blocks (pt-BR + en) embedded in the release body for non-technical end users. Trigger before calling `gh release create`, `gh release edit`, or any flow that touches a release body on this repo (including the `release` skill from fazer-ai-tools and any retroactive backfill of historical releases).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Release Notes (user-facing)

Every release cut from `fazer-ai/chatwoot` must embed bilingual user-notes blocks in the release body, written for non-technical end users (operators, admins, superadmins). Do not put implementation detail in these blocks.

## Branding — never "Chatwoot"

The product, as it reaches the end user, is **AurisChat** — that's the fork's brand. Inside the `<!-- user-notes:xx -->` markers (and in the in-app catalog), **never write "Chatwoot"**. Use **AurisChat** every time you'd otherwise reach for the upstream name.

The auto-generated `## Changes` commit list above the markers can keep `chatwoot` references (those are commit/path strings, not user-facing copy) — only the content **inside the markers** matters for branding.

If a string would have read "messages sent through Chatwoot" → write "messages sent through AurisChat". If a fix description would have started with "The Chatwoot panel..." → "O painel do AurisChat...".

## Two audiences, two depths

The same release pushes copy to two places that have **different readers and need different tone**:

| Surface | Reader | Tone |
|---|---|---|
| **GitHub release body** | Internal ops / admin / dev reading the release on GitHub | Can be moderately specific: concrete benefit + a brief scenario. Still no jargon, no PR refs, no module names — but you can name the area precisely ("AI handover messages", "WhatsApp delivery confirmation"). |
| **In-app catalog** (`config/release_notes.yml`, surfaced in *Notas de Versão* + *What's new* modal) | **Clinic secretary** running the AurisChat panel day-to-day | Plain conversational language, as if explaining to a colleague at the front desk. Only items the secretary would notice in her routine. Skip everything else. |

The two copies cover the same release but are NOT the same text. The in-app copy is a **secretary-friendly subset** of what's on GitHub.

### When to omit an item from the in-app copy

If the item is invisible to a clinic secretary in her day-to-day work, it does not belong in the in-app catalog. Examples of invisible:
- Internal queue / background processing hygiene
- Dead-letter / retry tuning
- Developer / ops tooling improvements
- Refactors with no behavior change
- Super-admin-only knobs the secretary never opens

When **everything** on the release is invisible to her, the in-app copy collapses to the single generic line (see "empty release" below). The GitHub body stays as drafted.

### Language anti-patterns (especially fatal in the in-app copy)

Avoid (rephrase or omit if you can't translate to her vocabulary):
- "monitoramento interno", "filas internas", "processamento", "eventos", "infraestrutura"
- "Sidekiq", "background jobs", "DeadSet", "queue", "worker"
- "retries", "race condition", "webhook", "API"
- "architecture", "refactor", "internal", "backend"
- Any internal initiative codename
- Vendor names the operator doesn't know (Baileys, Z-API, 360Dialog — say "WhatsApp" instead)

Stay in the vocabulary of someone scheduling appointments and answering patient messages.

## Required blocks (bilingual, both mandatory)

The release body must contain both an English block and a Portuguese block, in this order. Use H2 headings with country flags **outside** the blocks to separate the two sections visually on GitHub. The fazer.ai page only renders the content **inside** the `<!-- user-notes:xx:start -->` / `<!-- user-notes:xx:end -->` markers, so the H2 headings, the flags, and any commit list above are invisible there.

```markdown
## 🇺🇸 English

<!-- user-notes:en:start -->
... markdown in english ...
<!-- user-notes:en:end -->

## 🇧🇷 Português

<!-- user-notes:pt-BR:start -->
... markdown em português ...
<!-- user-notes:pt-BR:end -->
```

The two versions must be **equivalent in content**, written naturally in each language. They are **not** literal translations:
- en: "Drag conversations between columns faster."
- pt-BR: "Agora você pode arrastar conversas entre colunas mais rápido."

## Mirroring upstream releases

Downstream forks (e.g. `fazer-ai/chatwoot-pro`) that mirror a CE release must declare it with a blockquote at the top of each user-notes block, inside the markers. List all mirrored CE versions when there's more than one. CE releases never carry this marker.

```markdown
<!-- user-notes:en:start -->
> Includes changes from Chatwoot fazer.ai v4.12.0-fazer-ai.47.
...
<!-- user-notes:en:end -->

<!-- user-notes:pt-BR:start -->
> Inclui mudanças do Chatwoot fazer.ai v4.12.0-fazer-ai.47.
...
<!-- user-notes:pt-BR:end -->
```

## Audience and tone

Write for an **end user, not a developer**. Readers do not read code, do not know what a PR is, and do not care about refactors.

- **Present tense, active voice.** "Agora você pode reordenar etiquetas" / "You can now reorder labels". Not "Adicionada a possibilidade de…" / "Added the ability to…".
- **Lead with benefit, not implementation.** "Carregamento mais rápido em conexões lentas" / "Faster loading on slow connections" beats "Preload de componentes de rota no módulo internal-chat".
- **Plain language.** No jargon, no internal codenames, no function/file/library/module names.
- **No PR numbers, commit hashes, `#1234` references, or links to internal issues.**
- **Group by theme**, not by PR. Use these headers (omit empty ones, but keep the same set in both locales):

| pt-BR             | en              | When to use                                          |
| ----------------- | --------------- | ---------------------------------------------------- |
| `### ✨ Novidades` | `### ✨ What's new` | New user-visible features                            |
| `### ⚡ Melhorias` | `### ⚡ Improvements` | Refinements to existing features (perf, UX, polish) |
| `### 🐛 Correções` | `### 🐛 Fixes`   | Bugs the user might have noticed                      |

## Full release body example

The release body should preserve the auto-generated `## Changes` commit list at the top and append both locale sections after it:

```markdown
## Changes

- feat(internal-chat): implement internal chat system for agents (#247)
- fix(signatures): allow admins to manage inbox signatures without explicit membership (#260)

## 🇺🇸 English

<!-- user-notes:en:start -->
### ✨ What's new

- **Internal agent chat.** Your team can now message each other right inside AurisChat, no extra tool needed.

### ⚡ Improvements

- **Faster navigation on slow connections.** Switching between conversations feels more responsive.

### 🐛 Fixes

- **Inbox signatures.** Admins can manage signatures without having to be a member of the inbox.
<!-- user-notes:en:end -->

## 🇧🇷 Português

<!-- user-notes:pt-BR:start -->
### ✨ Novidades

- **Chat interno entre agentes.** Sua equipe agora troca mensagens diretamente dentro do AurisChat, sem precisar de outra ferramenta.

### ⚡ Melhorias

- **Navegação mais rápida em conexões lentas.** A troca entre conversas ficou mais responsiva.

### 🐛 Correções

- **Assinaturas de caixas de entrada.** Administradores conseguem gerenciar assinaturas mesmo sem participar da caixa.
<!-- user-notes:pt-BR:end -->
```

Bold the change name, then a single short sentence describing the user benefit. Keep each item to 1 or 2 lines.

If a release has nothing user-visible, write a single generic line in both locales rather than dumping a PR list:

```markdown
## 🇺🇸 English

<!-- user-notes:en:start -->
Bug fixes and internal improvements.
<!-- user-notes:en:end -->

## 🇧🇷 Português

<!-- user-notes:pt-BR:start -->
Correções de bugs e melhorias internas.
<!-- user-notes:pt-BR:end -->
```

## Quality checklist (run before publishing)

Run this checklist on **both** locale blocks of **both** copies (GitHub body AND in-app catalog entry):

- [ ] Both `en` and `pt-BR` blocks are present, with the exact tag spelling shown above, and the `en` block comes first.
- [ ] Both sections are wrapped by `## 🇺🇸 English` / `## 🇧🇷 Português` H2 headings outside the markers (GitHub body only).
- [ ] Both blocks contain equivalent content (same items, same order, same themes), written naturally in each language. Not a literal translation.
- [ ] Headers use the localized header table above. Omit empty themes consistently across locales.
- [ ] Every item leads with a user benefit, not an implementation detail.
- [ ] **No "Chatwoot" anywhere in the user-notes content** — use AurisChat. (The `## Changes` commit list at the top of the GitHub body is exempt — it's not user-facing copy.)
- [ ] No PR numbers, commit hashes, file paths, function names, library names, or internal module names.
- [ ] No mention of internal initiatives, customers, deals, roadmap, or anything that would not make sense to an external operator.
- [ ] Each item is understandable by someone who has never opened the codebase.
- [ ] Items are present-tense, benefit-led, 1 to 2 lines.
- [ ] **In-app copy specifically:** every surviving item passes the "would the clinic secretary notice this in her routine?" test. If not, drop it from the in-app copy (the GitHub body can keep it).
- [ ] Empty release: one generic line in both locales, never an empty block, never one block missing.

## Look at examples first

Before drafting, read the user-notes blocks from recent releases in this repo to match tone:

```bash
gh release list --limit 5
gh release view <tag> --json body -q .body
```

The references behind this style are **Linear**, **Stripe**, **Notion**, and **Vercel** changelogs: short, benefit-led, grouped by theme, with the user as the protagonist.

## Drafting workflow

When invoked for a release (new or backfill):

1. Read the current release body via `gh release view <tag> --json body -q .body` (or the source commits via `git log <prev-tag>..<tag> --oneline`) to understand what shipped.
2. Filter the changes through "would a non-technical operator notice or care about this?". Drop everything that fails the filter.
3. Group what survived into Novidades / Melhorias / Correções.
4. Draft the **pt-BR** block first as the source language. Write naturally, lead with benefit.
5. Draft the **en** block. Equivalent content, natural English, not a word-for-word translation.
6. Assemble the full release body: keep the `## Changes` commit list at the top, then `## 🇺🇸 English` + the `en` block, then `## 🇧🇷 Português` + the `pt-BR` block. The `en` section always comes first in the rendered release body.
7. Run the quality checklist on both blocks.
8. Show the full proposed body to the user for approval **before** editing the release.
9. Only after approval, write the body to a temp file and apply it:
   - **For new releases**, pass the file via `gh release create <tag> --notes-file <file>`.
   - **For backfills / edits**, this version of `gh` does not have a `release edit` subcommand. Use the API directly:
     ```bash
     RELEASE_ID=$(gh api repos/<owner>/<repo>/releases/tags/<tag> --jq '.id')
     gh api -X PATCH "repos/<owner>/<repo>/releases/$RELEASE_ID" -F body=@<file>
     ```
10. **Draft the in-app catalog version separately.** The in-app *Notas de Versão* serves a different reader (clinic secretary), so the copy is usually **shorter and simpler** than the GitHub body — frequently a subset:
    - Walk each item that survived for GitHub through the "would the clinic secretary notice this?" filter.
    - Drop the ones that fail: internal queue cleanup, dead-letter tuning, dev tooling, super-admin-only knobs, retry / processing changes.
    - Rephrase the survivors in conversational secretary-friendly language (no "monitoring", "queues", "events", "processing", "infrastructure", vendor names).
    - If no item survives, the in-app copy collapses to the single generic line ("Correções de bugs e melhorias internas." / "Bug fixes and internal improvements.") — even when the GitHub body has multiple specific items.
11. **Update the in-app catalog file** (`config/release_notes.yml`). Prepend the secretary-friendly version. The product reads only this file at runtime — it never calls GitHub. Format:
    ```yaml
    ---
    - tag: v4.13.0-auris.1.12
      published_at: '2026-05-08T20:00:00Z'
      url: https://github.com/Tech-Auris/chatwoot/releases/tag/v4.13.0-auris.1.12
      notes:
        en: |-
          ### ⚡ Improvements

          - **...** ...
        pt_BR: |-
          ### ⚡ Melhorias

          - **...** ...
    ```
    The `en` and `pt_BR` values must contain only the markdown for the secretary copy (strip any `<!-- user-notes:xx -->` markers). Commit `config/release_notes.yml` to `develop` **before** cutting the release tag, so the tagged commit ships with the new entry. Cap the file at the most recent ~20 releases (drop the oldest entry when adding a new one) to keep the menu usable.

## Example: same release, two different copies

This illustrates how a release with both an operator-visible fix and an invisible-to-secretary cleanup gets phrased for each surface.

**GitHub body (more specific, the dev/admin reader can handle it):**
```markdown
### ⚡ Improvements

- **Cleaner background processing.** Old status events tied to messages sent outside AurisChat no longer build up as failures in our internal monitoring, making real send issues easier to spot.

### 🐛 Fixes

- **AI handover messages reach the patient.** When the assistant transferred the conversation to a human after a long gap, its closing message could stay marked as "sent" without ever arriving on WhatsApp. These now deliver normally.
```

**In-app catalog (secretary version, the cleanup is dropped entirely):**
```yaml
en: |-
  ### 🐛 Fixes

  - **AI message at handoff to the team.** When the assistant passes the conversation to the team after a while without replies, that closing message now reaches the patient on WhatsApp.
pt_BR: |-
  ### 🐛 Correções

  - **Mensagem da IA na passagem para a equipe.** Quando a assistente transfere a conversa para a equipe depois de um tempo sem respostas, essa mensagem de encerramento agora chega no WhatsApp do paciente.
```

The "background processing" item is real and worth recording on GitHub, but the secretary doesn't care and doesn't see it — so it disappears from the in-app copy.
