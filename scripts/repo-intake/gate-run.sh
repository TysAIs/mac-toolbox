#!/usr/bin/env bash
# gate-run.sh — POST-INSTALL, PRE-RUN gate for a project directory.
# Lighter than gate-clone.sh: the code is already on disk and presumably
# inspected at intake; this re-checks dependency CVEs + secrets in the
# worktree right before `uv run` / `npm run` / first execution.
#
# Usage: gate-run.sh <project-dir> [--strict]
set -u
DIR="${1:-}"; STRICT=0
for arg in "$@"; do case "$arg" in --strict) STRICT=1 ;; esac; done
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: gate-run.sh <dir> [--strict]" >&2; exit 3; }

worst=0
note() { echo "$@"; }
max() { [ "$1" -gt "$worst" ] && worst="$1" || true; }

command -v osv-scanner >/dev/null 2>&1 || { echo "GATE ERROR: osv-scanner missing (docs/tooling-policy.md)"; exit 2; }

osv-scanner scan source "$DIR" --format json >/dev/null 2>&1
rc=$?
case $rc in
  0) note "[osv-scanner] clean" ;;
  1) note "[osv-scanner] FINDINGS — known-vulnerable dependencies present"; max 1 ;;
  *) note "[osv-scanner] error exit $rc"; max 2 ;;
esac

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$DIR" --no-git --exit-code 1 \
    --report-format json --report-path "/tmp/gate-run-gitleaks-$$.json" >/dev/null 2>&1
  rc=$?
  case $rc in
    0) note "[gitleaks] clean (worktree)" ;;
    1) note "[gitleaks] FINDINGS — report: /tmp/gate-run-gitleaks-$$.json"; max 1 ;;
    *) note "[gitleaks] error exit $rc"; max 2 ;;
  esac
fi

if command -v trivy >/dev/null 2>&1; then
  trivy fs --exit-code 1 --severity HIGH,CRITICAL --quiet "$DIR" >/dev/null 2>&1
  rc=$?
  case $rc in
    0) note "[trivy] clean" ;;
    1) note "[trivy] FINDINGS HIGH/CRITICAL"; max 1 ;;
    *) note "[trivy] error exit $rc"; max 2 ;;
  esac
else
  note "[trivy] skipped (optional phase 2)"
fi

if [ "$worst" -eq 0 ]; then echo "GATE RESULT: PASS"; exit 0; fi
if [ "$worst" -eq 2 ]; then echo "GATE RESULT: FAIL (tool/environment problem)"; exit 2; fi
if [ "$STRICT" -eq 1 ]; then echo "GATE RESULT: FAIL (--strict)"; exit 1; fi
echo "GATE RESULT: WARN (review findings before running this project)"
exit 1
