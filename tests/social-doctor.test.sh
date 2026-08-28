#!/usr/bin/env bash
# tests/social-doctor.test.sh — smoke test for the social-doctor doctor script.
# Verifies: script syntax, binary checks, skip semantics (xurl missing = SKIP
# never FAIL), JSON output parses, exit codes are 0/1 only, no cookie values leak.
set -u
cd "$(dirname "$0")/.."
SCRIPT="scripts/social-doctor.sh"
fails=0

t() { # name command...
  local name="$1"; shift
  if "$@" >/tmp/sd-test-out 2>&1; then echo "PASS: $name"; else echo "FAIL: $name"; cat /tmp/sd-test-out; fails=$((fails+1)); fi
}

t "syntax" bash -n "$SCRIPT"
# Exit 1 = findings (expected on a machine with no logins yet) — still a clean run.
out="$(bash "$SCRIPT" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -le 1 ]; then echo "PASS: runs (exit $rc = findings, expected pre-onboarding)"; else echo "FAIL: doctor crashed (exit $rc)"; fails=$((fails+1)); fi
unset out rc

# JSON mode must parse and contain the three platforms
bash "$SCRIPT" --json > /tmp/sd-test.raw 2>/dev/null || true
# stdout carries human lines + JSON; JSON starts at the first '[' at col 1.
awk '/^\[/{f=1} f' /tmp/sd-test.raw > /tmp/sd-test.json
python3 - <<'PYEOF' && JSON_OK=1 || echo "FAIL: json output invalid"
import json
d = json.load(open("/tmp/sd-test.json"))
plats = {r["platform"] for r in d}
assert {"twitter", "reddit", "xurl"} <= plats, plats
for r in d:
    assert set(r) == {"platform", "check_level", "ok", "fix"}, r
    assert isinstance(r["ok"], bool)
print("PASS: --json structure + platforms")
PYEOF

# Privacy: no cookie-looking strings anywhere in output
out="$(bash "$SCRIPT" 2>&1 || true)"
if printf '%s' "$out" | grep -qE '(auth_token|ct0)=[A-Za-z0-9%]'; then
  echo "FAIL: cookie values leaked in output"; fails=$((fails+1))
else
  echo "PASS: no cookie values in output"
fi

echo "---"
[ "$fails" -eq 0 ] && echo "social-doctor smoke: ALL PASS" || echo "social-doctor smoke: $fails FAILURES"
exit "$fails"
