#!/usr/bin/env bash
# install.sh
# Initialises the full local memory workspace for OpenClaw.
# Run once after cloning this repo. Safe to re-run — never overwrites
# existing files.
#
# Usage:
#   bash install.sh
#   bash install.sh --workspace /custom/path   # override workspace location

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# Parse optional --workspace flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()   { echo "  ✅  $*"; }
skip() { echo "  ⏭️   $* (already exists, skipped)"; }
info() { echo "  ℹ️   $*"; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Memento — Workspace Installer        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check dependencies
for cmd in jq openclaw node python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "  ❌  Missing dependency: $cmd"
    [[ "$cmd" == "jq" ]]       && echo "      Fix: sudo apt install -y jq"
    [[ "$cmd" == "node" ]]     && echo "      Fix: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"
    [[ "$cmd" == "openclaw" ]] && echo "      Fix: npm install -g openclaw"
    [[ "$cmd" == "python3" ]]  && echo "      Fix: sudo apt install -y python3"
    exit 1
  fi
done

# Check build-essential (gcc is the reliable proxy)
if ! command -v gcc &>/dev/null; then
  echo "  ❌  build-essential not installed (required by node-llama-cpp)"
  echo "      Fix: sudo apt install -y build-essential"
  exit 1
fi

echo ""
info "Workspace: $WORKSPACE"
echo ""

LLAMA_FAILED=0
CONFIG_FAILED=0

# ── Create directory structure ────────────────────────────────────────────────
echo "── Creating memory directory structure ──"

declare -a DIRS=(
  "$WORKSPACE/memory/episodic"
  "$WORKSPACE/memory/semantic"
  "$WORKSPACE/memory/procedural"
  "$WORKSPACE/memory/snapshots"
)

for d in "${DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    skip "$d"
  else
    mkdir -p "$d"
    ok "Created $d"
  fi
done

echo ""

# ── Copy templates ────────────────────────────────────────────────────────────
echo "── Installing template files ──"

declare -A TEMPLATES=(
  ["$TEMPLATES_DIR/SESSION-STATE.md"]="$WORKSPACE/SESSION-STATE.md"
  ["$TEMPLATES_DIR/RECENT_CONTEXT.md"]="$WORKSPACE/RECENT_CONTEXT.md"
  ["$TEMPLATES_DIR/MEMORY.md"]="$WORKSPACE/MEMORY.md"
  ["$TEMPLATES_DIR/HEARTBEAT.md"]="$WORKSPACE/HEARTBEAT.md"
)

for src in "${!TEMPLATES[@]}"; do
  dest="${TEMPLATES[$src]}"

  if [[ "$dest" == *"HEARTBEAT.md" ]]; then
    HEARTBEAT_MARKER="<!-- END MEMENTO HEARTBEAT -->"
    if [[ ! -f "$dest" ]]; then
      cp "$src" "$dest"
      ok "Installed $dest"
    elif grep -qF "$HEARTBEAT_MARKER" "$dest" 2>/dev/null; then
      skip "Memento heartbeat tasks already present in $dest"
    else
      real_lines=$(grep -cE '^[^[:space:]#]' "$dest" 2>/dev/null) || real_lines=0
      if [[ "$real_lines" -eq 0 ]]; then
        # Empty or comments-only — replace entirely
        cp "$src" "$dest"
        ok "Replaced empty/comment-only $dest with Memento heartbeat tasks"
      else
        # Has real content — append Memento section with separator
        printf '\n\n---\n\n' >> "$dest"
        cat "$src" >> "$dest"
        ok "Appended Memento heartbeat tasks to existing $dest"
        info "To remove later, delete everything from '## HEARTBEAT — Memento' to '$HEARTBEAT_MARKER'."
      fi
    fi

  elif [[ -f "$dest" ]]; then
    skip "$dest"
  else
    cp "$src" "$dest"
    ok "Installed $dest"
  fi
done

# ── Integrate memento-protocol into SOUL.md ───────────────────────────────────
echo ""
echo "── Integrating Memento protocol into SOUL.md ──"

SOUL_FILE="$WORKSPACE/SOUL.md"
PROTOCOL_FILE="$SCRIPT_DIR/memento-protocol.md"
MARKER="<!-- END MEMENTO PROTOCOL -->"

if [[ -f "$SOUL_FILE" ]]; then
  if grep -qF "$MARKER" "$SOUL_FILE" 2>/dev/null; then
    skip "Memento protocol already present in $SOUL_FILE"
  else
    # Append with a clear separator so it can be found and removed if needed
    printf '\n\n---\n\n' >> "$SOUL_FILE"
    cat "$PROTOCOL_FILE" >> "$SOUL_FILE"
    ok "Appended Memento protocol to existing $SOUL_FILE"
    info "Your existing SOUL.md content was preserved. The protocol block starts after '---'."
    info "To remove it later, delete everything from '## MEMENTO PROTOCOL' to '$MARKER'."
  fi
else
  cp "$PROTOCOL_FILE" "$SOUL_FILE"
  ok "Created $SOUL_FILE from memento-protocol.md"
fi

echo ""

# ── Ensure pnpm is available ──────────────────────────────────────────────────
echo "── Checking pnpm ──"

if command -v pnpm &>/dev/null; then
  ok "pnpm found: $(pnpm --version)"
else
  echo "  ⚠️   pnpm not found — installing via npm..."
  if npm install -g pnpm; then
    ok "pnpm installed: $(pnpm --version)"
  else
    echo "  ❌  Failed to install pnpm. Run manually: npm install -g pnpm"
    exit 1
  fi
fi

echo ""

# ── Verify node-llama-cpp binding ─────────────────────────────────────────────
echo "── Verifying node-llama-cpp ──"
# node-llama-cpp is ESM-only — must use import(), never require()

OPENCLAW_DIR="$(npm root -g)/openclaw"

check_llama() {
  (cd "$OPENCLAW_DIR" && node --input-type=module \
    -e "import('node-llama-cpp').then(() => process.exit(0)).catch(() => process.exit(1))" \
    2>/dev/null)
}

check_llama_verbose() {
  (cd "$OPENCLAW_DIR" && node --input-type=module \
    -e "import('node-llama-cpp').then(() => { console.log('OK'); process.exit(0); }).catch(e => { console.error('Import error:', e.message); process.exit(1); })" \
    2>&1)
}

if check_llama; then
  ok "node-llama-cpp binding loads correctly"
else
  echo "  ⚠️   node-llama-cpp binding not ready — attempting rebuild automatically..."
  if [[ -d "$OPENCLAW_DIR" ]]; then
    echo "  ── pnpm approve-builds ──"
    (cd "$OPENCLAW_DIR" && echo "node-llama-cpp" | pnpm approve-builds 2>&1) || true
    echo "  ── pnpm rebuild node-llama-cpp ──"
    set +e
    (cd "$OPENCLAW_DIR" && pnpm rebuild node-llama-cpp 2>&1)
    REBUILD_EXIT=$?
    set -e
    echo "  rebuild exit code: $REBUILD_EXIT"
    echo "  ── import() diagnostic ──"
    set +e
    check_llama_verbose
    set -e
    echo ""
    if check_llama; then
      ok "node-llama-cpp rebuilt and verified"
    else
      echo "  ❌  Auto-rebuild failed — paste everything above this line in the chat."
      echo "      Also run and paste:"
      echo "      ls $OPENCLAW_DIR/node_modules/node-llama-cpp/dist/"
      echo "      node --version"
      LLAMA_FAILED=1
    fi
  else
    echo "  ❌  OpenClaw not found at: $OPENCLAW_DIR"
    echo "      Contents of npm root: $(ls "$(npm root -g)")"
    LLAMA_FAILED=1
  fi
fi

echo ""

# ── Verify memory-manager skill ───────────────────────────────────────────────
echo "── Verifying memory-manager skill ──"

MM_PATH="$WORKSPACE/skills/memory-manager"
if [[ -d "$MM_PATH" ]]; then
  ok "memory-manager skill found at $MM_PATH"
else
  echo "  ⚠️   memory-manager skill not installed. Install it:"
  echo "       clawhub install memory-manager"
  echo "       (or manually extract the audited zip to $MM_PATH)"
fi

echo ""

# ── Patch openclaw.json with local embedding config ───────────────────────────
echo "── Patching openclaw.json ──"

CONFIG="$HOME/.openclaw/openclaw.json"

EMBEDDING_PATCH='{
  "agents": {
    "defaults": {
      "compaction": {
        "mode": "safeguard",
        "memoryFlush": { "enabled": true }
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
    }
  }
}'

if [[ ! -f "$CONFIG" ]]; then
  echo "  ⚠️   $CONFIG not found — has OpenClaw been run at least once?"
  echo "       Run: openclaw   (let it initialise, then re-run install.sh)"
  CONFIG_FAILED=1
else
  # Always remove the invalid batch key if present (left by earlier Memento versions)
  if jq -e '.agents.defaults.memorySearch.batch' "$CONFIG" &>/dev/null; then
    jq 'del(.agents.defaults.memorySearch.batch)' "$CONFIG" > "${CONFIG}.tmp" \
      && mv "${CONFIG}.tmp" "$CONFIG"
    ok "Removed invalid agents.defaults.memorySearch.batch key"
  fi

  if jq -e '.agents.defaults.memorySearch.provider == "local"' "$CONFIG" &>/dev/null; then
    ok "openclaw.json already has local embedding provider — skipping"
  else
    # Back up before touching anything
    cp "$CONFIG" "${CONFIG}.bak"
    ok "Backed up original config to ${CONFIG}.bak"

    # Deep-merge the patch (. * patch preserves all existing keys)
    if jq ". * $EMBEDDING_PATCH" "$CONFIG" > "${CONFIG}.tmp" && \
       jq empty "${CONFIG}.tmp" 2>/dev/null; then
      mv "${CONFIG}.tmp" "$CONFIG"
      ok "Patched openclaw.json with local embedding config"
    else
      rm -f "${CONFIG}.tmp"
      echo "  ❌  jq patch failed — config left unchanged, backup at ${CONFIG}.bak"
      CONFIG_FAILED=1
    fi
  fi
fi

echo ""

# ── Install Memento skill ─────────────────────────────────────────────────────
echo "── Installing Memento skill ──"

SKILL_DEST="$WORKSPACE/skills/memento"
SKILL_SRC="$SCRIPT_DIR/skills/memento"

if [[ -f "$SKILL_DEST/SKILL.md" ]]; then
  skip "$SKILL_DEST/SKILL.md"
else
  mkdir -p "$SKILL_DEST"
  cp "$SKILL_SRC/SKILL.md" "$SKILL_DEST/SKILL.md"
  ok "Installed Memento skill at $SKILL_DEST"
fi

echo ""
echo "── Enabling memory-core plugin ──"

set +e
PLUGIN_LIST=$(openclaw plugins list 2>/dev/null)
set -e

if echo "$PLUGIN_LIST" | grep -q "memory-core.*loaded"; then
  ok "memory-core plugin already loaded"
elif echo "$PLUGIN_LIST" | grep -q "memory-core"; then
  set +e
  openclaw plugins enable memory-core 2>&1
  ENABLE_EXIT=$?
  set -e
  if [[ $ENABLE_EXIT -eq 0 ]]; then
    ok "memory-core plugin enabled"
  else
    echo "  ⚠️   Could not enable memory-core — try manually: openclaw plugins enable memory-core"
  fi
else
  echo "  ⚠️   memory-core plugin not found in plugin list"
fi
echo "── Seeding initial memory ──"

EPISODIC_DIR="$WORKSPACE/memory/episodic"
WELCOME_FILE="$EPISODIC_DIR/$(date +%Y-%m-%d)-memento-install.md"

if [[ -f "$WELCOME_FILE" ]]; then
  skip "$WELCOME_FILE"
else
  cat > "$WELCOME_FILE" << WELCOMEEOF
# Memento Installed — $(date -u '+%Y-%m-%d %H:%M UTC')

Memento local memory system successfully installed and configured.

## Setup Summary

- Embedding model: nomic-embed-text-v1.5 Q4_K_M (local, no API key)
- Vector store: SQLite + sqlite-vec + FTS5 hybrid search (70% vector / 30% BM25)
- Memory tiers: episodic / semantic / procedural
- Protocol: 4-rule SOUL protocol (write-ahead, ADD/UPDATE/DELETE/NOOP, tier routing, heartbeat)
- Workspace: $WORKSPACE

## What to do next

The agent should read SESSION-STATE.md and RECENT_CONTEXT.md at every session
start, write facts to memory before responding, and run a heartbeat capture
every ~10 turns. See memento-protocol.md for the full rule set.
WELCOMEEOF
  ok "Created welcome memory entry at $WELCOME_FILE"
fi

echo ""
echo "── Restarting gateway ──"

# Ensure node-llama-cpp model cache directory exists before indexing
# (missing dir causes ENOENT on the .ipull → .gguf atomic rename during first download)
mkdir -p "$HOME/.node-llama-cpp/models"
ok "Ensured ~/.node-llama-cpp/models/ exists"

set +e
openclaw gateway restart 2>&1
GATEWAY_EXIT=$?
set -e

if [[ $GATEWAY_EXIT -eq 0 ]]; then
  ok "Gateway restarted"
  echo "  ℹ️   Waiting 5s for gateway to come up..."
  sleep 5
else
  echo "  ⚠️   Gateway restart returned exit code $GATEWAY_EXIT"
  echo "      Waiting 5s anyway and attempting index..."
  sleep 5
fi

echo ""
echo "── Indexing memory ──"

set +e
openclaw memory index 2>&1
INDEX_EXIT=$?
set -e

if [[ $INDEX_EXIT -eq 0 ]]; then
  ok "Memory indexed successfully"
else
  echo "  ⚠️   First index attempt failed (likely model download race) — retrying in 5s..."
  sleep 5
  set +e
  openclaw memory index 2>&1
  INDEX_EXIT=$?
  set -e
  if [[ $INDEX_EXIT -eq 0 ]]; then
    ok "Memory indexed successfully (retry)"
  else
    echo "  ⚠️   Memory index failed — run manually once gateway is stable: openclaw memory index"
  fi
fi

echo ""


echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Workspace:    $WORKSPACE"
echo "  Hot RAM:      $WORKSPACE/SESSION-STATE.md"
echo "  Rolling log:  $WORKSPACE/RECENT_CONTEXT.md"
echo "  Long-term:    $WORKSPACE/MEMORY.md"
echo "  Memory tiers: $WORKSPACE/memory/{episodic,semantic,procedural}"
echo ""

# Collect remaining manual steps
MANUAL_STEPS=()

if [[ "${LLAMA_FAILED:-0}" == "1" ]]; then
  MANUAL_STEPS+=("Rebuild node-llama-cpp:  cd \$(npm root -g)/openclaw && pnpm approve-builds && pnpm rebuild node-llama-cpp")
fi

MM_PATH="$WORKSPACE/skills/memory-manager"
if [[ ! -d "$MM_PATH" ]]; then
  MANUAL_STEPS+=("Install memory-manager:  clawhub install memory-manager")
fi

if [[ "${CONFIG_FAILED:-0}" == "1" ]]; then
  MANUAL_STEPS+=("Patch openclaw.json manually — see README Step 2 (run OpenClaw once first if config is missing)")
fi

if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
  echo "  ── Action required ──────────────────────────────────────"
  for step in "${MANUAL_STEPS[@]}"; do
    echo "  👉  $step"
  done
  echo ""
fi

echo "  ── Verify everything is running ───────────────────────"
echo "     openclaw memory status --deep"
echo ""
