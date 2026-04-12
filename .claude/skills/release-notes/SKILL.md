---
name: release-notes
description: Use this skill whenever you are about to cut, edit, or backfill a GitHub release for fazer-ai/chatwoot. Generates the bilingual user-notes blocks (pt-BR + en) embedded in the release body for non-technical end users. Trigger before calling `gh release create`, `gh release edit`, or any flow that touches a release body on this repo (including the `release` skill from fazer-ai-tools and any retroactive backfill of historical releases).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Release Notes (user-facing)

Every release cut from `fazer-ai/chatwoot` must embed bilingual user-notes blocks in the release body, written for non-technical end users (operators, admins, superadmins). Do not put implementation detail in these blocks.

## Required blocks (bilingual, both mandatory)

```markdown
<!-- user-notes:pt-BR:start -->
... markdown em português ...
<!-- user-notes:pt-BR:end -->

<!-- user-notes:en:start -->
... markdown in english ...
<!-- user-notes:en:end -->
```

The two versions must be **equivalent in content**, written naturally in each language. They are **not** literal translations:
- pt-BR: "Agora você pode arrastar conversas entre colunas mais rápido."
- en: "Drag conversations between columns faster."

If you cannot write a real equivalent in one of the locales, write a **generic line in both** instead of leaving one missing or pasting raw Google Translate output.

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

## Format inside each block

```markdown
<!-- user-notes:pt-BR:start -->
### ✨ Novidades

- **Chat interno entre agentes.** Sua equipe agora troca mensagens diretamente dentro do Chatwoot, sem precisar de outra ferramenta.

### ⚡ Melhorias

- **Navegação mais rápida em conexões lentas.** A troca entre conversas ficou mais responsiva.

### 🐛 Correções

- **Assinaturas de caixas de entrada.** Administradores conseguem gerenciar assinaturas mesmo sem participar da caixa.
<!-- user-notes:pt-BR:end -->

<!-- user-notes:en:start -->
### ✨ What's new

- **Internal agent chat.** Your team can now message each other right inside Chatwoot, no extra tool needed.

### ⚡ Improvements

- **Faster navigation on slow connections.** Switching between conversations feels more responsive.

### 🐛 Fixes

- **Inbox signatures.** Admins can manage signatures without having to be a member of the inbox.
<!-- user-notes:en:end -->
```

Bold the change name, then a single short sentence describing the user benefit. Keep each item to 1 or 2 lines.

If a release has nothing user-visible, write a single generic line in both locales rather than dumping a PR list:

```markdown
<!-- user-notes:pt-BR:start -->
Correções de bugs e melhorias internas.
<!-- user-notes:pt-BR:end -->

<!-- user-notes:en:start -->
Bug fixes and internal improvements.
<!-- user-notes:en:end -->
```

## Quality checklist (run before publishing)

Run this checklist on **both** locale blocks:

- [ ] Both `pt-BR` and `en` blocks are present, with the exact tag spelling shown above.
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
4. Draft the **pt-BR** block first. Write naturally, lead with benefit.
5. Draft the **en** block. Equivalent content, natural English, not a word-for-word translation.
6. Run the quality checklist on both blocks.
7. Show the proposed blocks to the user for approval **before** editing the release.
8. Only after approval, edit the release with `gh release edit <tag> --notes-file <file>` (preserve any existing technical body content above/below the blocks if present, or replace as the user instructs).
