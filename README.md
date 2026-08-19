# HearthVault

<p align="center"><img src="docs/hero.png" alt="HearthVault — a brain of glowing embers inside a stone hearth" width="720"></p>

**Tiered markdown memory for Claude Code.** An Obsidian-compatible vault your agent maintains for you: a small hot tier injected at every session start, deeper tiers read on demand, and a weekly janitor that keeps the hot tier from growing. No database, no embeddings — markdown, git, three hooks, one scheduled agent.

## 🚀 Install

One line, no manual cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/BorisNikolic/hearthvault/main/install.sh | bash
```

The installer asks two questions — your vault's name (`Brain`, `MyBrain`, or a full path) and your first project/client folder's name — then does everything:

1. creates the vault as a git repo, with your project folder already named,
2. installs the three hooks and the `/vault-cleanup` command,
3. registers the hooks in `~/.claude/settings.json` (idempotent, with a backup),
4. **asks to schedule the weekly janitor** (macOS launchd, Mondays 08:07) — answer `y` and it installs and loads the schedule itself, no manual `launchctl` step. Skip it and you can still run `/vault-cleanup` by hand anytime.

Non-interactive / from a clone:

```bash
git clone https://github.com/BorisNikolic/hearthvault.git && cd hearthvault
./install.sh MyBrain Acme   # creates ~/MyBrain with an Acme/ project folder
```

Requirements: [Claude Code](https://claude.com/claude-code), `git`, `jq`. The launchd schedule is macOS-only (hooks are portable; use cron/systemd elsewhere).

After install: start a Claude Code session in the vault — the hot cache loads automatically. Settings live in `~/.config/hearthvault/config` (vault path, extra work dirs that receive context, freshness window).

**Uninstall** (removes hooks, command, schedule, config — **never your notes**):

```bash
curl -fsSL https://raw.githubusercontent.com/BorisNikolic/hearthvault/main/uninstall.sh | bash
```

Your vault and its full git history stay on disk untouched; delete that folder yourself if you truly want the data gone.

**Obsidian is optional.** The mechanism is plain markdown, shell hooks, and git — the agent reads and greps files directly, and `[[wikilinks]]` are just a linking convention it follows. Opening the vault in [Obsidian](https://obsidian.md) gives *you* a nice human interface (graph view, backlinks, search), but nothing breaks without it. No plugins required either way.

## 🔥 How it works

Sessions are ephemeral; the vault remembers. Content settles downward through three tiers, so the always-injected part stays a few thousand tokens forever:

```mermaid
flowchart LR
    S[Claude Code<br/>session]
    J[Janitor<br/>weekly + on demand]
    subgraph V[vault - markdown + git]
        H[HOT - always injected<br/>Now.md index +<br/>fresh Now/*.md caches]
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

| Tier | Contents | In context |
|---|---|---|
| **🔥 Hot** | `Now.md` index (≤10 KB) + `Now/<topic>.md` caches touched in the last 14 days (~5 KB each) | injected at every session start |
| **🪵 Warm** | `Tasks/` (durable record per ticket), `Decisions/`, `People/` (profiles of collaborators) | agent Reads via wikilinks when relevant |
| **🧊 Cold** | `Now/Done/` archive, processed transcripts, full git history | never — nothing is deleted, it settles here |

The **session** writes only to its own topic's cache (parallel sessions never collide), overwrites instead of appending, and every edit auto-commits — git is the undo. The **janitor** (`/vault-cleanup`, weekly or manual) archives finished topics, compresses over-budget caches, files decisions verbatim, refreshes indexes, and validates links.

Relations between notes are a **small typed graph in frontmatter** (`owner`, `blocks`, `blocked_by`, `supersedes`, `covers`, `decided_by`, `relates_to`) — greppable, queryable, no graph database.

### 📥 The Inbox

Drop raw material into `Inbox/` — a meeting transcript, an exported doc, a pasted email. The SessionStart hook flags unprocessed files, so the next Claude Code session you start in the vault picks them up: it reads each file, extracts decisions into `Decisions/`, facts into the right topic notes, moves the raw file to `Inbox/Processed/`, and refreshes the hot cache. The weekly janitor does the same for anything left over. So processing isn't instant — nothing watches the folder — it happens at the start of your next vault session, which in practice is exactly when you'd want to talk about that meeting anyway. The agent is told to verify claims against reality before filing them (transcripts lie).

## 🧭 Principles

- The injected tier is a **cache with a budget**, not a journal.
- **Overwrite, don't append** — history lives in git; "Prior:" chains cap at 3.
- **Decisions move intact, never summarized.**
- **Nothing is deleted** — it settles down a tier.
- **One vault per client** — confidentiality isolation is structural, not disciplinary.
- **Discipline decays; schedules don't** — every rule is enforced by the janitor.

## 📄 License

MIT
