#!/bin/bash
# stamp-computer-control.sh — propagate the compact computer-control ladder
# from your policy file into EVERY agent SOUL.md (root + all profiles).
# Idempotent: safe to re-run. Backs up each SOUL.md first.
#
# Usage: scripts/stamp-computer-control.sh [HERMES_HOME]
set -euo pipefail

HERMES_HOME="${1:-${HERMES_HOME:-$HOME/.hermes}}"
POLICY="$HERMES_HOME/computer-control-policy.md"
[ -f "$POLICY" ] || { echo "ERROR: $POLICY not found" >&2; exit 1; }
[ -s "$POLICY" ] || { echo "ERROR: $POLICY is empty — reinstall or restore it" >&2; exit 1; }

VERSION=$(grep -m1 '^Version:' "$POLICY" | awk '{print $2}' || true)
if [ -z "${VERSION:-}" ]; then
  echo "ERROR: no 'Version:' line in $POLICY — fix the file, do not hand-edit souls" >&2
  exit 1
fi

BLOCK_START="<!-- BEGIN computer-control v$VERSION (generated — do not hand-edit) -->"
BLOCK_END="<!-- END computer-control -->"

LADDER='## Computer control (this machine)
You operate this Mac via a strict priority ladder: (1) a targeted CLI/skill if one exists — always cheapest and most reliable; (2) known AppleScript/JXA via osascript or mac.script(); (3) native-app GUI work via the Hermes-native cua-driver (`computer_use` tool) — background AX-tree reads, pid-scoped input, no focus-steal or cursor movement; (4) web tasks via browser-use / browser_exec, cua-driver / computer_use, or Brave CDP (port 9222) — never third-party closed-source browsers; (5) full-screen computer-use drivers as fallback only. Never move the physical cursor or force apps foreground. After one failed verified burst, switch approach — never repeat failed input. Permission errors: tell the user exactly which System Settings toggle to grant; do not retry.

## Resource hygiene (this machine)
Clean up after yourself: close every browser tab you opened when the task ends (≤2 per host; reuse existing tabs instead of opening duplicates), kill your own stuck/zombie worker processes, and verify tab count is back to baseline before calling a browser task done. A finished task that leaks tabs or processes is an incomplete task.'

STAMP_ONE() {
  local soul="$1"
  [ -f "$soul" ] || { echo "SKIP (missing): $soul"; return; }
  cp "$soul" "$soul.bak-stamp-$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
  # Strip ANY previous stamped block: complete pairs AND orphaned/partial ones
  # (e.g., a soul truncated mid-block must recover cleanly).
  python3 - "$soul" <<'PYEOF'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text()
t = re.sub(r"\n?<!-- BEGIN computer-control v.*?<!-- END computer-control -->\n?", "\n", t, flags=re.S)
# Orphan: a BEGIN whose END was lost (truncation). Cut BEGIN to EOF.
m = t.find("<!-- BEGIN computer-control")
if m != -1:
    t = t[:m]
p.write_text(t.rstrip("\n") + "\n")
PYEOF
  { echo ""; echo "$BLOCK_START"; echo "$LADDER"; echo "$BLOCK_END"; } >> "$soul"
  echo "STAMPED v$VERSION -> $soul"
}

STAMP_ONE "$HERMES_HOME/SOUL.md"
shopt -s nullglob
for soul in "$HERMES_HOME"/profiles/*/SOUL.md; do
  STAMP_ONE "$soul"
done

echo "Done. SSOT: $POLICY (v$VERSION). Edit the policy, re-run this script."
