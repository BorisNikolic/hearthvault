# HearthVault

**Tiered markdown memory for Claude Code.** A plain-Obsidian-vault memory system where an AI coding agent remembers your work across sessions — without ever bloating its context window.

Sessions are ephemeral; the vault is what remembers. HearthVault keeps a small **hot tier** that is injected automatically at session start, deeper tiers the agent reads only on demand, and a weekly **janitor** that keeps the hot tier from ever growing back.

No database, no embeddings, no extraction pipeline. Markdown files + git + three shell hooks + one scheduled agent.

## Why

The naive version of this system (inject a "current state" file at every session start) fails predictably: nothing ever expires, so the injected context grows unboundedly. This exact setup grew **3 KB → 298 KB (~75k tokens) in two months** before the mechanisms below were added. Context bloat isn't just cost — context-rot studies show model accuracy *degrades* as input grows.

The fixes are the ones the agent-memory field converged on (MemGPT/Letta's capped core memory, claude-mem's index-only injection, "sleep-time" consolidation agents), implemented in plain markdown:

1. a **recency window** — only recently-touched topic caches get injected,
2. **hard size budgets** with overflow moved down a tier,
3. **overwrite-don't-append** semantics — history lives in git, not in the cache,
4. a **scheduled janitor**, because write-time discipline alone always decays.

## How it works

```mermaid
flowchart LR
    S[Claude Code<br/>session]
    J[Janitor<br/>weekly + on demand]
    subgraph V[vault - markdown + git]
        H[HOT - always injected<br/>Now.md index +<br/>Now/*.md fresh caches]
        W[WARM - read on demand<br/>Tasks/ Decisions/ People/]
        C[COLD - never injected<br/>Now/Done/ + git history]
    end
    H -- "SessionStart hook injects" --> S
    S -- "overwrites its topic cache" --> H
    W -. "Read via wikilink" .-> S
    S -- "auto-commit every edit" --> C
    J -- "compresses, caps" --> H
    J -- "history down a tier" --> W
    J -- "done topics archived" --> C
```

**Three tiers:**

| Tier | Contents | Budget | When in context |
|---|---|---|---|
| **Hot** | `Now.md` (index + cross-cutting) and `Now/<topic>.md` caches touched in the last 14 days | ≤10 KB index, ~5 KB per cache | Injected at every session start (and after `/clear` or compaction) |
| **Warm** | `Tasks/` (durable per-ticket record), `Decisions/` (never summarized), `People/` (per-person profiles), hub note | — | Agent Reads them via wikilinks when relevant |
| **Cold** | `Now/Done/` archived caches, `Inbox/Processed/` raw transcripts, full git history | — | Never injected; nothing is ever deleted, it settles down here |

**Two actors:**

- **The session** gets the hot tier automatically, writes only to its own topic's cache (parallel sessions never collide), overwrites instead of appending, and every edit is auto-committed — git is the undo.
- **The janitor** (`/vault-cleanup`, scheduled weekly via launchd or run manually) archives finished topics, compresses over-budget caches into task notes, files durable decisions verbatim, refreshes indexes, and validates links + the typed-relation graph.

**A small knowledge graph, not a graph database:** relations between notes go in frontmatter as typed keys (`owner`, `blocks`, `blocked_by`, `supersedes`, `covers`, `decided_by`, `relates_to`) with wikilink values, so they're greppable and queryable. `People/` holds a profile per recurring collaborator — standing agreements, review preferences, open threads. A new relation key is added only the second time it's needed. (Why not a real graph DB? mem0 shipped one and removed it — 3x slower, 2x tokens, thin gains. At personal-vault scale, grep is a full graph scan in milliseconds.)

## What's in the box

```
hooks/
  vault-context.sh      SessionStart: inject hot tier (recency-windowed) + flag Inbox
  vault-autocommit.sh   PostToolUse(Write|Edit): auto-commit every vault change
  vault-stale-check.sh  Stop: nudge if a note changed but the cache wasn't refreshed
commands/
  vault-cleanup.md      the janitor procedure (/vault-cleanup slash command)
launchd/
  com.hearthvault.janitor.plist   weekly schedule template (macOS)
vault-template/
  CLAUDE.md             the conventions the agent follows (tiers, budgets, graph rules)
  Now.md, Now/, Inbox/, Client/{Tasks,Decisions,People,Setup}/
install.sh
```

## Install

Requirements: [Claude Code](https://claude.com/claude-code), `git`, `jq`. macOS for the launchd schedule (the hooks themselves are portable; use cron/systemd timers elsewhere).

```bash
git clone https://github.com/BorisNikolic/hearthvault.git
cd hearthvault
./install.sh ~/Brain        # or any vault path you like
```

The installer creates the vault (as a git repo), installs the hooks and the `/vault-cleanup` command, writes `~/.config/hearthvault/config`, prints the `settings.json` hook registration snippet, and offers to schedule the weekly janitor.

Then: rename `Client/` to your actual project, open the vault in Obsidian if you like graphs, and start a Claude Code session inside the vault or one of your configured work dirs. The agent picks up the conventions from the vault's `CLAUDE.md`.

## Daily use

- **Just work.** Sessions in your work dirs get the hot tier automatically and maintain the vault as a side effect (per the vault `CLAUDE.md`: decisions filed proactively, caches refreshed in the same turn, agreements recorded on people's profiles).
- **Drop raw material** (meeting transcripts, exports) into `Inbox/` — the next vault session processes it into structured notes.
- **Run `/vault-cleanup`** whenever things feel crufty; Monday's scheduled run does it anyway. Read `.janitor-report.md` after.
- **One vault per client.** Confidentiality isolation is structural, not disciplinary: a session for client A can never leak client B's context, because it's a different vault, a different repo, a different hook scope.

## Principles (the short version)

- The always-injected tier is a **cache with a budget**, not a journal. Target a few thousand tokens.
- **Overwrite, don't append.** New state replaces old; history lives in git and task notes. "Prior:" chains cap at 3.
- **Decisions are sacred** — moved intact, never summarized. Summaries lose exactly the details you'll need.
- **Nothing is deleted** — content settles downward through tiers; cold + git keep everything forever.
- **A wrong typed relation is worse than prose.** The janitor validates the graph; when unsure, write prose.
- **Discipline decays; schedules don't.** Every rule above is enforced by the janitor, not by hoping sessions behave.

## License

MIT
