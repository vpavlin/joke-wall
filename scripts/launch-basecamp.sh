#!/usr/bin/env bash
# Launch logos-basecamp with JokeWall plugin pre-configured.
#
# Usage:
#   ./scripts/launch-basecamp.sh
#   NSSA_WALLET_HOME_DIR=/my/wallet ./scripts/launch-basecamp.sh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROGRAM_BIN="$ROOT/methods/guest/target/riscv32im-risc0-zkvm-elf/docker/joke_wall.bin"

LOGOS_WORKSPACE_DIR="${LOGOS_WORKSPACE_DIR:-$(cd "$ROOT/../logos-workspace" 2>/dev/null && pwd || echo "")}"
BASECAMP_BIN="${BASECAMP_BIN:-$LOGOS_WORKSPACE_DIR/repos/logos-basecamp/result/bin/logos-basecamp}"

if [[ ! -f "$PROGRAM_BIN" ]]; then
    echo "ERROR: joke_wall.bin not found at $PROGRAM_BIN"
    echo "  Run 'make build' first."
    exit 1
fi
if [[ ! -f "$BASECAMP_BIN" ]]; then
    echo "ERROR: logos-basecamp not found at $BASECAMP_BIN"
    echo "  Set BASECAMP_BIN or LOGOS_WORKSPACE_DIR, or rebuild logos-basecamp."
    exit 1
fi

PROGRAM_ID_HEX=$(spel -p joke_wall inspect "$PROGRAM_BIN" 2>/dev/null \
    | sed -n 's/.*ImageID (hex bytes): \([0-9a-f]*\).*/\1/p')

if [[ -z "$PROGRAM_ID_HEX" || ${#PROGRAM_ID_HEX} -ne 64 ]]; then
    echo "ERROR: could not extract 64-char program ID from binary"
    echo "  'spel -p joke_wall inspect $PROGRAM_BIN' output:"
    spel -p joke_wall inspect "$PROGRAM_BIN" 2>&1 | sed 's/^/  /'
    exit 1
fi

echo "JokeWall Basecamp launcher"
echo "  Binary:     $PROGRAM_BIN"
echo "  Program ID: $PROGRAM_ID_HEX"
echo "  Wallet dir: ${NSSA_WALLET_HOME_DIR:-$ROOT/.scaffold/wallet}"
echo "  Basecamp:   $BASECAMP_BIN"
echo ""

exec env \
    NSSA_WALLET_HOME_DIR="${NSSA_WALLET_HOME_DIR:-$ROOT/.scaffold/wallet}" \
    NSSA_SEQUENCER_URL="${NSSA_SEQUENCER_URL:-http://127.0.0.1:3040}" \
    JOKE_WALL_PROGRAM_ID_HEX="$PROGRAM_ID_HEX" \
    "$BASECAMP_BIN"
