#!/usr/bin/env bash
# Reconstruct lib/ for the Beryl Clanker fork. The 175M dependency tree is NOT
# committed; this re-fetches it at the exact versions upstream Clanker pins (minus
# the Optimism monorepo, which only the removed ClankerToken needed), plus base-std.
#
# Run from contracts/berylpad/:  ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

UPSTREAM=https://github.com/clanker-devco/v4-contracts
UPSTREAM_SHA=b004c2edda29fa282a16d5d1441a26484f70b37f   # the fork base

echo "==> Fetching Clanker dep tree at pinned versions (optimism excluded)…"
TMP="$(mktemp -d)"
git clone -q "$UPSTREAM" "$TMP/up"
git -C "$TMP/up" checkout -q "$UPSTREAM_SHA"
git -C "$TMP/up" -c submodule."lib/optimism".update=none submodule update --init --recursive \
  lib/forge-std lib/openzeppelin-contracts lib/permit2 lib/universal-router lib/v4-core lib/v4-periphery

rm -rf lib && mkdir -p lib
for d in forge-std openzeppelin-contracts permit2 universal-router v4-core v4-periphery; do
  cp -R "$TMP/up/lib/$d" "lib/$d"
done
rm -rf "$TMP"
find lib -name '.git' -prune -exec rm -rf {} + 2>/dev/null || true

echo "==> Installing base-std (B20 precompile interfaces)…"
BASEFORGE="$HOME/.foundry/versions/base-v1.1.0:$HOME/.foundry/bin"
PATH="$BASEFORGE:$PATH" base-forge install base/base-std --no-git

echo "==> Done. Build with:  PATH=\"$BASEFORGE:\$PATH\" base-forge build"
