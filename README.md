# Memento — OpenClaw Local Memory

A fully local, zero-external-API persistent memory stack for
[OpenClaw](https://github.com/openclaw/openclaw), combining in-process
embeddings, hybrid SQLite vector/BM25 search, and a five-principle agent
protocol drawn from the rosepuppy skill and Mem0 research.

<img width="1457" height="955" alt="Screenshot from 2026-03-02 18-22-11" src="https://github.com/user-attachments/assets/d4859823-5ade-48d7-86d5-ac9ade71f681" />
<img width="1445" height="997" alt="Screenshot from 2026-03-02 18-21-58" src="https://github.com/user-attachments/assets/7718394c-8c84-48ae-b284-6d5047b65611" />



> 📊 **[Architecture Infographic](docs/infographic.html)** — visual overview
> of the full stack, write pipeline, and protocol rules.

---

## Architecture

| Layer | What | Why |
|-------|------|-----|
| **Embeddings** | `nomic-embed-text-v1.5 Q4` (~130 MB GGUF) via `node-llama-cpp` | In-process — no daemon, no API key |
| **Vector store** | `sqlite-vec` inside OpenClaw's SQLite | Zero extra services, 768-dim cosine search |
| **Keyword search** | FTS5 BM25 (built into SQLite) | Exact token matching for IDs, names, code symbols |
| **Hybrid search** | 70% vector + 30% BM25, 4× candidate pool | Best of both retrieval strategies |
| **Embedding cache** | SQLite cache (up to 50 000 entries) | Unchanged chunks never re-embedded |
| **Durability** | Pre-compaction memory flush | Agent writes notes before context compaction |
| **Organisation** | `memory-manager` skill (episodic / semantic / procedural) | Three-tier structure + compression snapshots |
| **Plugin slot** | `memory-core` (native OpenClaw baseline) | `memory_search` + `memory_get` tools |
| **Hot RAM** | `SESSION-STATE.md` | Instant re-orientation after crashes or restarts |
| **Rolling summary** | `RECENT_CONTEXT.md` | Third retrieval channel, refreshed every ~10 turns |
| **Protocol** | `SOUL.md` (five-principle rules) | Tells the agent *when* to write — not just *how* |

**What this is NOT:**
- No Ollama daemon · No Qdrant · No LanceDB · No OpenAI/Gemini API key
- No Mem0 SaaS (privacy preserved — we only borrowed their published research ideas)

---

## Protocol Design — Where the Rules Come From

Most memory solutions give you tools but no protocol for *when* to use them.
This setup encodes five principles from three sources:

| Source | Idea borrowed |
|--------|--------------|
| **rosepuppy/memory-complete** (ClawHub) | Write-ahead log, SESSION-STATE.md hot RAM, heartbeat cadence |
| **Mem0 research paper** (ECAI 2025, arXiv:2504.19413) | Two-phase ADD/UPDATE/DELETE/NOOP write pipeline |
| **memory-manager** (ClawHub) | Three-tier episodic / semantic / procedural routing |

The Mem0 write pipeline is the key insight: before appending any new fact to
semantic memory, the agent searches first and decides whether to ADD, UPDATE,
DELETE-then-ADD (if contradictory), or NOOP. This keeps the memory store
coherent at write time — contradictions and duplicates never accumulate.

---

## Prerequisites

- Ubuntu 24.04 (tested; should work on any Linux x64)
- Node.js >= 22 — `node --version`
- OpenClaw installed — `openclaw --version`
- `pnpm` — installed in Step 1 below
- `jq` — used by `memory-manager` scripts

---

## Step 1 — Build the `node-llama-cpp` Native Binding

`install.sh` will install `pnpm` automatically if it's missing. If you prefer
to do this step manually first:

```bash
npm install -g pnpm   # only needed if pnpm isn't already on your system
cd $(npm root -g)/openclaw
pnpm approve-builds        # select node-llama-cpp if prompted
pnpm rebuild node-llama-cpp

# Verify — must use import(), NOT require()
# ❌ Wrong: node -e "require('node-llama-cpp')"  ← throws ERR_REQUIRE_ASYNC_MODULE
# ✅ Right:
node --input-type=module -e "import('node-llama-cpp').then(() => console.log('OK'))"
# Expected: OK
```

> **Note:** On systems without a compatible GPU (e.g. VirtualBox), a Vulkan
> warning is printed. OpenClaw falls back to CPU mode automatically — harmless.

---

## Step 2 — Configure `openclaw.json`

> **`install.sh` handles the embedding config automatically** using `jq`.
> It backs up your existing config to `openclaw.json.bak` before patching,
> and skips this step entirely if the local provider is already configured.
> You only need to read this section if the auto-patch failed or you prefer
> to configure manually.

Open `~/.openclaw/openclaw.json` and add the following blocks. Do **not**
replace your existing config — merge these keys in.

### Inside `agents.defaults`

```jsonc
"compaction": {
  "mode": "safeguard",
  "memoryFlush": {
    "enabled": true
  }
},
"memorySearch": {
  "enabled": true,
  "provider": "local",
  "local": {
    "modelPath": "hf:nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.Q4_K_M.gguf"
  },
  "query": {
    "hybrid": {
      "enabled": true,
      "vectorWeight": 0.7,
      "textWeight": 0.3,
      "candidateMultiplier": 4
    }
  },
  "cache": {
    "enabled": true,
    "maxEntries": 50000
  }
}
```

### Inside `plugins`

```jsonc
"slots": {
  "memory": "memory-core"
},
"allow": ["memory-core"],
"entries": {
  "memory-core": {
    "enabled": true
  }
}
```

### Multi-agent shared memory (optional)

```jsonc
"memorySearch": {
  "store": {
    "path": "~/.openclaw/memory/shared.sqlite"
  },
  "extraPaths": ["~/.openclaw/workspace/MEMORY.md"]
}
```

Restart after editing:

```bash
openclaw gateway restart
```

The first restart auto-downloads the nomic GGUF (~130 MB) to
`~/.node-llama-cpp/models/`. One-time only.

---

## Step 3 — Install `memory-manager` Skill

```bash
sudo apt install jq -y
clawhub install memory-manager
# or manually from audited zip:
# mkdir -p ~/.openclaw/workspace/skills/memory-manager
# unzip audited.zip -d ~/.openclaw/workspace/skills/memory-manager/
```

> **Security:** Always vet ClawHub skills with `skill-guard` before installing.
> Audit for `memory-manager v1.0.0`: 🟢 SAFE (0 critical, 0 warnings,
> local file ops only, no network calls).

---

## Step 4 — Initialise the Workspace

```bash
bash install.sh
```

This script creates the memory directory tree, copies templates, and verifies
the key dependencies. It never overwrites existing files.

### SOUL.md — safe merge, not overwrite

The memory protocol lives in `memento-protocol.md`. `install.sh` handles
integration automatically:

- **If `SOUL.md` already exists** — the protocol block is *appended* after a
  `---` separator. Your existing identity, persona, and project rules are fully
  preserved. The added block is clearly delimited so it can be removed cleanly
  if needed.
- **If no `SOUL.md` exists** — `memento-protocol.md` is copied in as the
  starting point.

To remove the protocol later, delete everything from `## MEMENTO PROTOCOL`
to `<!-- END MEMENTO PROTOCOL -->` in your `SOUL.md`.

---

## Verification

```bash
openclaw memory status --deep
```

Expected:
```
Provider: local
Model: hf:nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.Q4_K_M.gguf
Embeddings: ready
Vector: ready  (768 dims)
FTS: ready
Embedding cache: enabled
```

---

## The Five Protocol Rules

See [`SOUL.md`](SOUL.md) for the full agent instructions.

| # | Rule | Trigger | Source |
|---|------|---------|--------|
| 0 | **Read SESSION-STATE + RECENT_CONTEXT first** | Session start | rosepuppy |
| 1 | **Write-ahead** | User gives concrete fact/decision | rosepuppy |
| 2 | **ADD / UPDATE / DELETE / NOOP** | Before any write to semantic/ | Mem0 research |
| 3 | **Tier routing** (episodic/semantic/procedural) | Every write | memory-manager |
| 4 | **Heartbeat capture every ~10 turns** | Cadence — no user signal needed | rosepuppy + Mem0 |

---

## Benchmark

```bash
chmod +x scripts/benchmark-memory.sh
./scripts/benchmark-memory.sh
```

Run once per model: swap `modelPath`, restart gateway, re-run to compare.

| Query | gemma-300m (600 MB) | nomic-embed v1.5 Q4 (130 MB) |
|-------|--------------------|-----------------------------|
| "what database are we using and why" | ✅ 0.396 · 6.24s | ✅ 0.425 · 5.38s |
| "user communication style" | ❌ No matches · 6.16s | ✅ 0.398 · 4.89s |
| "auth token expiry details" | ❌ No matches · 5.99s | ✅ 0.370 · 4.87s |

nomic: 3/3 recalled, ~1s faster per query, 470 MB smaller.

---

## Useful CLI Commands

```bash
# Status
openclaw memory status --deep
openclaw memory status --deep --index   # force reindex

# Search
openclaw memory search "your query"
time openclaw memory search "your query"

# SQLite inspection
sqlite3 ~/.openclaw/memory/main.sqlite "SELECT COUNT(*) FROM chunks;"
sqlite3 ~/.openclaw/memory/main.sqlite "SELECT COUNT(*) FROM embedding_cache;"
sqlite3 ~/.openclaw/memory/main.sqlite "SELECT path, chunk_count FROM files ORDER BY updated_at DESC;"

# memory-manager
bash ~/.openclaw/workspace/skills/memory-manager/detect.sh
bash ~/.openclaw/workspace/skills/memory-manager/stats.sh

# Model cache
ls -lh ~/.node-llama-cpp/models/
rm -rf ~/.node-llama-cpp/models/ggml-org   # remove gemma if downloaded

# Gateway
openclaw gateway restart
tail -f ~/.openclaw/openclaw.log | grep -i "embed\|memory\|llama\|index"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ERR_REQUIRE_ASYNC_MODULE` when testing node-llama-cpp | Used `require()` — node-llama-cpp is ESM-only | Use `node --input-type=module -e "import('node-llama-cpp').then(() => console.log('OK'))"` — never `require()` |
| `pnpm: command not found` | pnpm not installed | `npm install -g pnpm` (install.sh does this automatically) |
| `Embeddings: unavailable` | Wrong model path or GGUF not downloaded | Check `modelPath`; restart gateway |
| Low indexed file count | Empty dirs from install.sh | Normal — grows as `.md` files are written |
| Vulkan warning on startup | No GPU (VirtualBox) | Harmless — CPU fallback |
| `clawhub install` rate limit | ClawHub API | Retry or install manually from zip |
| `memory_search` returns nothing | Index dirty | `openclaw memory status --deep --index` |
| `jq: command not found` | jq missing | `sudo apt install jq -y` |
| Session loses context after restart | SESSION-STATE not written | Ensure SOUL.md is loaded; check write-ahead rule is firing |

---

## Repository Structure

```
.
├── README.md
├── memento-protocol.md           ← Agent memory protocol (appended to SOUL.md by install.sh)
├── LICENSE
├── LICENSE-ANALYSIS.md
├── install.sh                    ← One-time workspace initialiser
├── docs/
│   ├── infographic-overview.html ← Visual overview (dark, big-cards style)
│   └── infographic.html          ← Precision comparison table
├── templates/
│   ├── SESSION-STATE.md          ← Hot RAM template
│   ├── RECENT_CONTEXT.md         ← Rolling summary template
│   └── MEMORY.md                 ← Long-term memory template
└── scripts/
    └── benchmark-memory.sh       ← Model comparison benchmark
```

---

## License

Released under MIT license 

Kudos to my brother Maurizio for the project name suggestion :)


---

## References

- [OpenClaw](https://github.com/openclaw/openclaw)
- [nomic-embed-text-v1.5 GGUF](https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF)
- [node-llama-cpp](https://github.com/withcatai/node-llama-cpp)
- [sqlite-vec](https://github.com/asg017/sqlite-vec)
- [Mem0 paper — arXiv:2504.19413](https://arxiv.org/abs/2504.19413)
- [ClawHub skill registry](https://clawhub.ai)
