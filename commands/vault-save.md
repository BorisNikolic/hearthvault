---
description: File the current conversation's valuable content into the HearthVault vault as structured notes
---

Save the current conversation's durable content into the vault configured in `~/.config/hearthvault/config` (`VAULT`, default `~/Brain`). Read the vault's `CLAUDE.md` first for structure and note conventions.

## Variants

- `/vault-save` — analyze the conversation, pick the most valuable durable content (decisions, facts, task progress), file it where it belongs.
- `/vault-save decision <name>` — create a `Decisions/YYYY-MM-DD <name>.md` note (What / Why / Who / Supersedes).
- `/vault-save session` — append a dated session summary to the relevant task note (or create the `Tasks/` note if missing): what was done, what was learned, what's open.
- `/vault-save <name>` — save with that title, inferring the right location.

## Rules

1. Update existing notes over creating new ones — check the hub note and existing task notes first.
2. Follow the vault's conventions: frontmatter, typed relations, absolute dates, wikilink footer, dense prose.
3. Refresh the matching hot cache in the same turn (the topic's `Now/<topic>.md`, or `Now.md` for cross-cutting) and bump its timestamp.
4. Don't commit manually — a PostToolUse hook auto-commits vault writes.
5. Report back one line per file touched.
