#!/usr/bin/env bash
# gate-clone.sh — PRE-CLONE / PRE-INSTALL security gate for an unknown repo.
#
# Usage: gate-clone.sh <repo-url-or-local-dir> [--strict]
#
# What it runs (independently, results fanned in):
#   stage 1 (always):  gitleaks  — leaked secrets in git history/worktree
#                      osv-scanner — known CVEs in dependency lockfiles
#   stage 2 (conditional): skillspector --no-llm — agent-skill/MCP threat scan,
#                      run ONLY when the target contains SKILL.md, mcp.json, or
#                      .cursor/rules (skill/MCP-shaped content).
#   phase 2 (optional): trivy fs if trivy is installed.
#
# Exit codes: 0 = clean · 1 = findings (WARN, or FAIL with --strict) ·
#             2 = required tool missing (never silently pass) ·
#             3 = usage error
set -u

STRICT=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) TARGET="$arg" ;;
  esac
done
[ -n "$TARGET" ] || { echo "usage: gate-clone.sh <repo-url-or-dir> [--strict]" >&2; exit 3; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=""
cleanup() { [ -n "$WORK" ] && [ -d "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# --- Resolve target to a local directory -------------------------------------
if [ -d "$TARGET" ]; then
  DIR="$TARGET"
elif [[ "$TARGET" == *:* || "$TARGET" == *github.com* ]]; then
  # Shallow clone into a throwaway dir so scanners see history + lockfiles.
  WORK="$(mktemp -d)/repo"
  git clone --quiet --depth 50 "$TARGET" "$WORK" 2>/dev/null || {
    echo "GATE ERROR: could not shallow-clone $TARGET"; exit 2; }
  DIR="$WORK"
else
  echo "GATE ERROR: $TARGET is neither a local dir nor a cloneable URL" >&2
  exit 3
fi

overall=0   # worst aggregated status

echo "== repo-intake gate: $DIR =="

# --- Install checks at top: a missing binary must never silently pass --------
for bin in gitleaks osv-scanner; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "GATE ERROR: '$bin' not installed. See docs/tooling-policy.md §Install."
    exit 2
  }
done

# --- Stage 1a: secrets ---------------------------------------------------------
gitleaks detect --source "$DIR" --exit-code 1 \
  --report-format json --report-path "/tmp/gate-gitleaks-$$.json" >/dev/null 2>&1
rc_gitleaks=$?
if [ $rc_gitleaks -eq 0 ]; then
  echo "[gitleaks] clean"
else
  echo "[gitleaks] FINDINGS — report: /tmp/gate-gitleaks-$$.json (exit $rc_gitleaks; 1=findings, other=tool error)"
fi

# --- Stage 1b: dependency CVEs -------------------------------------------------
osv_out="$(osv-scanner scan source "$DIR" --format json 2>/dev/null)"
rc_osv=$?
if [ $rc_osv -eq 0 ]; then
  echo "[osv-scanner] clean"
elif [ $rc_osv -eq 127 ] || ! command -v osv-scanner >/dev/null 2>&1; then
  echo "[osv-scanner] MISSING TOOL"; rc_osv=2
else
  hits="$(printf '%s' "$osv_out" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("?"); raise SystemExit
print(sum(len(p.get("vulnerabilities",[])) for r in d.get("results",[]) for p in r.get("packages",[])))' 2>/dev/null)"
  echo "[osv-scanner] FINDINGS: ${hits:-?} known CVEs in dependencies"
  printf '%s' "$osv_out" > "/tmp/gate-osv-$$.json"
fi

# --- Stage 2 (conditional): skill/MCP-shaped content → skillspector ------------
rc_sk=0
if find "$DIR" -maxdepth 3 \( -name 'SKILL.md' -o -name 'mcp.json' -o -name '.mcp.json' \) 2>/dev/null | grep -q .; then
  if command -v skillspector >/dev/null 2>&1; then
    skillspector scan "$DIR" --no-llm --format sarif --output "/tmp/gate-skillspector-$$.sarif" >/dev/null 2>&1
    rc_sk=$?
    [ $rc_sk -eq 0 ] && echo "[skillspector] clean (static-only)" \
      || echo "[skillspector] FINDINGS (exit $rc_sk) — SARIF: /tmp/gate-skillspector-$$.sarif"
  else
    echo "[skillspector] MISSING for skill-shaped repo — treat as FAIL until installed"
    rc_sk=2
  fi
else
  echo "[skillspector] skipped (no SKILL.md / mcp.json present)"
fi

# --- Phase 2 (optional): trivy fs ----------------------------------------------
rc_trivy=0
if command -v trivy >/dev/null 2>&1; then
  trivy fs --exit-code 1 --severity HIGH,CRITICAL --quiet "$DIR" >/dev/null 2>&1
  rc_trivy=$?
  [ $rc_trivy -eq 0 ] && echo "[trivy] clean" \
    || echo "[trivy] FINDINGS (HIGH/CRITICAL, exit $rc_trivy)"
else
  echo "[trivy] skipped (not installed — optional phase 2)"
fi

# --- Fan-in --------------------------------------------------------------------
worst=0
for rc in "$rc_gitleaks" "${rc_osv:-0}" "$rc_sk" "$rc_trivy"; do
  [ "$rc" -gt "$worst" ] && worst="$rc"
done

case "$worst" in
  0) echo "GATE RESULT: PASS (clean)";   exit 0 ;;
  2) echo "GATE RESULT: FAIL (tool missing — fix environment, do not skip the gate)"
     exit 2 ;;
  *)
    if [ "$STRICT" -eq 1 ]; then
      echo "GATE RESULT: FAIL (--strict, findings present)"; exit 1
    fi
    echo "GATE RESULT: WARN (findings present — review reports above before uv/npm install or first run)"
    exit 1
    ;;
esac
