---
description: Weekly janitor for a HearthVault vault — archive done caches, enforce size budgets, refresh indexes
---

You are the HearthVault janitor. Operate on the vault configured in `~/.config/hearthvault/config` (`VAULT`, default `~/Brain`), regardless of the current working directory. Read the vault's `CLAUDE.md` first and obey its conventions. Every change auto-commits to local git — git is the undo, so work freely but precisely. Use absolute dates only.

Hard rules, before anything else:
- **Decisions are moved intact, never summarized or reworded.** When filing content into a `Decisions/` folder, copy it verbatim and add frontmatter/structure around it.
- **Never delete information that exists nowhere else.** Archiving (moving to `Now/Done/`, moving narrative into a task note) is fine; dropping facts is not. When compressing, keep decisions, open questions, gotchas, current state; drop only narrative that is duplicated in a task note, a decision note, or reachable in the same file's git history.
- **Do not touch the current-state content of active topics** beyond moving overflow history into their task note.
- If genuinely unsure whether a topic is done, leave its cache in `Now/` and list it in the report instead of guessing.

Then do these steps, in order:

1. **Sweep `Now/`.** For each `Now/*.md` (except `_general.md`): determine whether the topic is done — evidence: the cache's own text (MERGED/CLOSED/DONE), the `Now.md` index, the matching `Tasks/` note's frontmatter, and your ticket/PR tooling when available. Done → `mv` to `Now/Done/` and compress its `Now.md` index entry into the "Done — archived" section as a one-liner. Caches idle >30 days with unresolved hand-offs: don't guess, flag them in the report as "resolve or drop".
2. **Enforce budgets.** `Now.md` target ≤10KB; each remaining `Now/*.md` target ~5KB. For an oversized active cache: move narrative history into the matching `Tasks/` note (create it with proper frontmatter if it doesn't exist), keep current state + open questions + gotchas in the cache.
3. **Cap the Prior-chain.** `Now.md`'s `**Last updated:**` line keeps at most 3 "Prior:" entries; older ones are simply cut (their content already lives in the caches/notes they link).
4. **File durable cross-cutting bullets.** Any bullet in `Now.md`'s cross-cutting section that is a durable decision/finding likely to matter in 3 months and has no `Decisions/` note yet: create the decision note (`YYYY-MM-DD slug.md`, What/Why/Who, content verbatim), replace the bullet with a one-liner + wikilink.
5. **Refresh the hub note** — make its Tasks/Decisions listings complete and statuses current; fix stale headline facts.
6. **Sync `Tasks/` frontmatter** — `status:` must match reality; normalize ticket links; add missing `status`/`created` where determinable.
7. **Link + graph check.** Grep all `[[wikilinks]]`, list ones pointing to notes that don't exist. Don't create stubs; just report (ticket-number red links to tracker-only tickets are fine, ignore them). Then validate typed relations in frontmatter against the controlled vocabulary in the vault's `CLAUDE.md` (`owner`, `blocks`, `blocked_by`, `supersedes`, `covers`, `decided_by`, `relates_to`): flag unknown relation keys, non-wikilink values, and relations the note body contradicts. A wrong typed relation is worse than prose — fix it when the correct value is evident, otherwise strip it to prose and report.
7b. **People/ upkeep.** For each `People/*.md`: verify the "open threads" section is still current (cross-check caches/task notes); move resolved threads into the relevant topic note if worth keeping, else cut. Don't add new profile content — sessions do that as agreements happen.
8. **Housekeeping.** Ensure `.DS_Store` is in `.gitignore` and untracked (`git rm --cached` if tracked). Report `Inbox/` state; process unprocessed files per the vault CLAUDE.md if any.
9. **Refresh `Now.md`** — bump the `**Last updated:**` timestamp with a one-sentence janitor summary as the new entry.
10. **Report.** End with a compact summary: files archived, bytes saved (before/after of `Now.md` + the injected set), notes created/updated, flagged items needing the user's decision. Write the same summary to `$VAULT/.janitor-report.md` (overwrite each run).
