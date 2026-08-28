#!/bin/bash
# T5: full sandbox retest of mac-toolbox installer (with scripts install)
set -u
SB=$(mktemp -d)
mkdir -p "$SB/bin" "$SB/.hermes/profiles/alpha"
for p in . profiles/alpha; do printf 'You are TestBot %s.\n' "$p" > "$SB/.hermes/$p/SOUL.md"; done

HERMES_HOME="$SB/.hermes" /Users/itxji/TysAIs/mac-toolbox/install.sh > "$SB/install.log" 2>&1
echo "install rc=$?"

echo "--- scripts installed:"
ls "$SB/.hermes/scripts/" 2>/dev/null

echo "--- watchdog runs from installed copy:"
"$SB/.hermes/scripts/resource-watchdog.sh"

policy_hits=$(grep -c 'Resource hygiene' "$SB/.hermes/computer-control-policy.md")
soul_root=$(grep -c 'Resource hygiene (this machine)' "$SB/.hermes/SOUL.md")
soul_alpha=$(grep -c 'Resource hygiene (this machine)' "$SB/.hermes/profiles/alpha/SOUL.md")
echo "policy hygiene hits=$policy_hits  SOUL root=$soul_root  alpha=$soul_alpha"

M1=$(md5 -q "$SB/.hermes/computer-control-policy.md")
HERMES_HOME="$SB/.hermes" /Users/itxji/TysAIs/mac-toolbox/install.sh >/dev/null 2>&1
if [ "$(md5 -q "$SB/.hermes/computer-control-policy.md")" = "$M1" ]; then
  echo "idempotent OK"
else
  echo "IDEMPOTENCY FAIL"
fi

rm -rf "$SB"
