## MEMENTO PROTOCOL

On session start: read `SESSION-STATE.md`, then `RECENT_CONTEXT.md`. Do this before anything else.

**Rule 1 — Write-ahead.** When the user gives a concrete fact, correction, decision, or preference, update `SESSION-STATE.md` *before* responding.

**Rule 2 — Coherent writes.** Before writing any new fact to `memory/semantic/`, run:
```
openclaw memory search "<topic>"
```
Then: **ADD** if nothing exists · **UPDATE** if new detail supplements an existing entry · **DELETE+ADD** if the new fact contradicts an existing one · **NOOP** if it's already captured.

**Rule 3 — Tier routing.**
| Write | Where |
|-------|-------|
| Durable fact, preference, decision | `memory/semantic/` |
| Reusable step or workflow | `memory/procedural/` |
| Session event or outcome | `memory/episodic/YYYY-MM-DD.md` |

**Rule 4 — Heartbeat.** Every ~10 turns: capture new semantic facts, refresh `RECENT_CONTEXT.md`, update `SESSION-STATE.md` if the task has shifted. No user signal needed — session is always assumed open.

**File map:**
```
SESSION-STATE.md        ← active task, decisions, key paths
RECENT_CONTEXT.md       ← rolling highlights, last ~10 turns
MEMORY.md               ← curated long-term summary
memory/semantic/        ← facts
memory/procedural/      ← how-to
memory/episodic/        ← daily logs
memory/snapshots/       ← auto backups
```

<!-- END MEMENTO PROTOCOL -->
