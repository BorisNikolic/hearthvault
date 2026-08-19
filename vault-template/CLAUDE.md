# My work vault (HearthVault)

This vault is the persistent memory for my work. Claude maintains it. Plain Markdown, Obsidian wikilinks (`[[Note Name]]`), YAML frontmatter. Local git: every change is auto-committed by a hook — never ask before writing, git is the undo.

## Structure

- `Now.md` — hot cache **index + cross-cutting** only (workstream list, cross-topic decisions, tooling). Keep it short; it's a cache, not a journal. Bump its `**Last updated:** YYYY-MM-DD HH:MM` line (time included, since notes land several times a day). **The "Prior:" chain holds max 3 entries** — new state overwrites old, history lives in the per-topic caches, task notes and git, never in this line. Target size ≤10KB.
- `Now/<topic>.md` — **per-topic hot cache** (one per ticket/workstream, e.g. `Now/TICKET-123.md`). This is where active work goes. **Each session writes only the file for the topic it's working on** — this is what keeps parallel sessions from clobbering each other. Overwrite the file (don't append), keep it tight, and bump its `**Updated:** YYYY-MM-DD HH:MM` line. Use `Now/_general.md` for active work not tied to a topic. When a topic is fully done, move its cache to `Now/Done/` **in the same session that closes it** (don't delete — for many topics the cache is the only record), and update the `Now.md` index. Target ~5KB per cache; when one outgrows that, move narrative history into the topic's task note and keep only current state. **The SessionStart hook injects only caches touched in the last 14 days** — older ones stay indexed in `Now.md` and are one Read away, so nothing is lost by staying tight.
- `Client/Client.md` — hub note (index). Rename `Client/` to your project or client's name. Keep its links current when adding/removing notes. One vault per client — never mix clients in one vault.
- `Client/Tasks/` — one note per ticket: scope, decisions, log, open questions. Frontmatter: `status: in-progress|done`, `jira:`/`ticket:` link.
- `Client/Decisions/` — one file per durable decision: `YYYY-MM-DD <slug>.md`. Body: **What** was decided, **Why**, **Who** (and where — meeting/DM/channel), **Supersedes** (link if it overrides an earlier decision). Small decisions that belong to a single topic go in that topic's note instead; use Decisions/ for anything cross-topic or likely to matter in 3 months.
- `Client/People/` — one note per recurring person (teammates, QA, PM): role, standing agreements, review preferences, open threads. Update the person's note when an agreement is made or a preference shows up in a review — same discipline as decisions. Don't log routine activity there; it's a profile, not a journal.
- `Client/Setup/` — machine/tooling notes.
- `Inbox/` — drop zone for raw material (meeting transcripts, exports).

## Typed relations (frontmatter)

Relations between notes go in frontmatter as typed keys with wikilink values (quoted, list form), so they are greppable/queryable — the prose keeps the story, the frontmatter keeps the graph:

- `owner:` — who owns the ticket/work (`"[[Person Name]]"` or `me`)
- `blocks:` / `blocked_by:` — dependency between topics
- `supersedes:` — this note replaces an earlier one (decisions, specs)
- `covers:` — this topic's work also covers/duplicates another
- `decided_by:` — person(s) who made the call (decision notes)
- `relates_to:` — generic association when no typed key fits

Example: `blocked_by: ["[[TICKET-155]]"]`. Rules: use only keys from this list; add a new key to this list only the **second** time you need it, never speculatively; a wrong typed relation is worse than prose, so when unsure put it in prose instead. Wikilinks to tracker-only tickets (no note in the vault) are fine.

## Inbox processing

When a session starts here and `Inbox/` has unprocessed files: read each, extract decisions → `Decisions/` or the relevant task note, facts → the relevant topic notes, then move the raw file to `Inbox/Processed/`. Verify claims against code/reality before writing them into notes (transcripts lie). Refresh the relevant `Now/` cache afterwards.

## Hot cache discipline

After any meaningful vault change (task progress, new decision, resolved question), refresh the matching hot cache **in the same turn**: the topic's `Now/<topic>.md` for topic work, or `Now.md` for cross-cutting. Bump the `**Updated:**` timestamp. A Stop hook reminds you if a note changed but no cache was refreshed. **Only touch the cache file for what you actually worked on** — never rewrite another topic's `Now/` file from a session that wasn't about it.

## Janitor (weekly consolidation)

A scheduled job (launchd, Mondays) runs `claude -p "/vault-cleanup"` in this vault; you can also run `/vault-cleanup` manually anytime. It archives done caches to `Now/Done/`, enforces the size budgets, caps the Prior-chain, files durable cross-cutting bullets into `Decisions/`, refreshes the hub note + `Tasks/` frontmatter, reports broken wikilinks, validates typed frontmatter relations against the vocabulary above, and keeps `People/` open-threads current. Rules it must obey: decisions are **moved intact, never summarized**; active caches' current-state content is preserved; git is the undo.

## Style

- Frontmatter on every note: `tags`, `created` (and `status`/ticket link for tasks).
- Footer links: `Links: [[Client]] · [[related note]]`.
- Absolute dates always (2026-06-11, never "today").
- Dense and factual; no filler. Update existing notes rather than creating near-duplicates.
