---
name: memento
description: >
  Local-first persistent memory system for OpenClaw agents. Zero external APIs —
  embeddings run in-process via nomic-embed-text-v1.5 + sqlite-vec hybrid search.
  Owns all memory search, write, and three-tier routing (episodic/semantic/procedural).
  Use when: saving facts, decisions, or preferences across sessions; searching past
  context; recovering after crashes or compaction. Pairs with memory-manager skill
  for compression detection and snapshots. Governs mandatory write-ahead,
  ADD/UPDATE/DELETE/NOOP deduplication, and heartbeat capture.
emoji: 🧠
tags: [memory, local, embeddings, persistence, protocol]
---

# Memento — Local Memory System

Memento gives you persistent, searchable, private memory. No cloud. No API keys.
Embeddings run in-process. Everything lives in `~/.openclaw/workspace/`.

## When to use this skill

- User asks what was discussed, decided, or preferred in a past session
- A concrete fact, correction, or decision needs to be saved
- Session is about to end or context is getting long
- User asks about memory, context, or "what do you remember"
- Heartbeat fires (~10 turns) and meaningful content has accumulated

## Core tools

| Tool | When |
|------|------|
| `openclaw memory search "<query>"` | Recall — before answering questions about past context |
| `openclaw memory index` | Re-index if status shows `Dirty: yes` |
| `openclaw memory status --deep` | Health check — embeddings, vector, FTS, chunk count |

## The four rules (mandatory)

**Rule 1 — Write-ahead.** Concrete fact, correction, decision, or preference → update `SESSION-STATE.md` *before* responding.

**Rule 2 — Coherent writes.** Before writing to `memory/semantic/`, search first. Then: ADD · UPDATE · DELETE+ADD · NOOP.

**Rule 3 — Tier routing.** Facts/decisions → `memory/semantic/` · Steps/workflows → `memory/procedural/` · Session events → `memory/episodic/YYYY-MM-DD.md`

**Rule 4 — Heartbeat.** Every ~10 turns:
1. If `memory-manager` skill is installed: run `~/.openclaw/skills/memory-manager/detect.sh` — if WARNING or CRITICAL, run `snapshot.sh` immediately before continuing
2. Capture new semantic facts → `memory/semantic/`
3. Refresh `RECENT_CONTEXT.md`
4. Update `SESSION-STATE.md` if task shifted

## Session start (mandatory)

Read these two files before doing anything else:
1. `SESSION-STATE.md` — active task, key paths, recent decisions
2. `RECENT_CONTEXT.md` — highlights from recent turns

## File map

```
SESSION-STATE.md        ← hot RAM: active task, decisions, key paths
RECENT_CONTEXT.md       ← rolling highlights, last ~10 turns
MEMORY.md               ← curated long-term summary
memory/semantic/        ← durable facts and preferences
memory/procedural/      ← reusable workflows and how-tos
memory/episodic/        ← daily session logs
memory/snapshots/       ← compression backups (auto-managed)
```

## Stack

- Embeddings: `nomic-embed-text-v1.5 Q4_K_M` (~84MB GGUF, in-process, no daemon)
- Store: SQLite + `sqlite-vec` (768-dim cosine) + FTS5 BM25, 70/30 hybrid search
- Cache: up to 50,000 embedding entries, unchanged chunks never re-embedded

## OpenClaw compatibility

Requires OpenClaw ≥ 2026.3.8 with `memory-core` stock plugin enabled (default).
If `memory-manager` workspace skill is also installed, it is scoped to compression
monitoring only (`detect.sh` + `snapshot.sh`) — Memento owns all search, write, and
routing. Do not enable `memory-lancedb` alongside Memento (alternative backend, conflicts).
