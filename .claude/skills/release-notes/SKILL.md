---
name: release-notes
description: Use this skill whenever you are about to cut, edit, or backfill a GitHub release for fazer-ai/chatwoot. Generates the bilingual user-notes blocks (pt-BR + en) embedded in the release body for non-technical end users. Trigger before calling `gh release create`, `gh release edit`, or any flow that touches a release body on this repo (including the `release` skill from fazer-ai-tools and any retroactive backfill of historical releases).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Release Notes (user-facing)

Every release cut from `fazer-ai/chatwoot` must embed bilingual user-notes blocks in the release body, written for non-technical end users (operators, admins, superadmins). Do not put implementation detail in these blocks.

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

- **Internal agent chat.** Your team can now message each other right inside Chatwoot, no extra tool needed.

### ⚡ Improvements

- **Faster navigation on slow connections.** Switching between conversations feels more responsive.

### 🐛 Fixes

- **Inbox signatures.** Admins can manage signatures without having to be a member of the inbox.
<!-- user-notes:en:end -->

## 🇧🇷 Português

<!-- user-notes:pt-BR:start -->
### ✨ Novidades

- **Chat interno entre agentes.** Sua equipe agora troca mensagens diretamente dentro do Chatwoot, sem precisar de outra ferramenta.

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

Run this checklist on **both** locale blocks:

- [ ] Both `en` and `pt-BR` blocks are present, with the exact tag spelling shown above, and the `en` block comes first.
- [ ] Both sections are wrapped by `## 🇺🇸 English` / `## 🇧🇷 Português` H2 headings outside the markers.
- [ ] Both blocks contain equivalent content (same items, same order, same themes), written naturally in each language. Not a literal translation.
- [ ] Headers use the localized header table above. Omit empty themes consistently across locales.
- [ ] Every item leads with a user benefit, not an implementation detail.
- [ ] No PR numbers, commit hashes, file paths, function names, library names, or internal module names.
- [ ] No mention of internal initiatives, customers, deals, roadmap, or anything that would not make sense to an external operator.
- [ ] Each item is understandable by someone who has never opened the codebase.
- [ ] Items are present-tense, benefit-led, 1 to 2 lines.
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
