#!/usr/bin/env bash
# benchmark-memory.sh
# Tests embedding model retrieval quality and speed against a known memory fixture.
#
# Usage:
#   ./scripts/benchmark-memory.sh
#
# Run once per model: swap modelPath in openclaw.json, restart the gateway,
# then run this script again to compare results.
#
# Requirements:
#   - OpenClaw gateway running
#   - openclaw CLI available on PATH

set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
MEMORY_DIR="$WORKSPACE/memory"
FIXTURE="$MEMORY_DIR/benchmark-test.md"

# ── Create fixture ──────────────────────────────────────────────────────────
echo "📄 Writing benchmark fixture to $FIXTURE"
mkdir -p "$MEMORY_DIR"

cat > "$FIXTURE" << 'EOF'
# Benchmark Test Memory

## User Preferences
The user prefers concise technical responses and dislikes unnecessary verbosity.
They work primarily with Python and TypeScript.

## Project Decisions
We decided to use PostgreSQL over MongoDB for the main database because of transaction support.
The API follows REST conventions with JSON responses.

## System Configuration
The gateway runs on Ubuntu 24.04 inside VirtualBox.
Memory is handled by node-llama-cpp with local embeddings.

## Recent Conversations
Discussed authentication strategy: JWT with 15 minute expiry and refresh token rotation.
User asked about Docker networking and port forwarding between containers.

## Personal Notes
The user's name is Alex. They prefer morning meetings and are based in Europe (CET timezone).
EOF

# ── Force reindex ─────────────────────────────────────────────────────────────
echo "🔄 Forcing reindex (this may take a few seconds)..."
openclaw memory status --deep --index > /dev/null 2>&1
sleep 2

# ── Run queries ───────────────────────────────────────────────────────────────
QUERIES=(
  "what database are we using and why"
  "user communication style"
  "auth token expiry details"
)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BENCHMARK RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for query in "${QUERIES[@]}"; do
  echo ""
  echo "▶ Query: \"$query\""
  { time openclaw memory search "$query" 2>&1 | head -5; } 2>&1
  echo "────────────────────────────────────────────────────────"
done

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -f "$FIXTURE"
echo ""
echo "✅ Benchmark complete. Fixture removed."
echo ""
echo "To compare models:"
echo "  1. Change 'modelPath' in ~/.openclaw/openclaw.json"
echo "  2. Run: openclaw gateway restart"
echo "  3. Run this script again"
