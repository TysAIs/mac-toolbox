#!/usr/bin/env bash
# check-versions.sh — drift-check the repo-intake gate's binaries against
# the minimum versions verified in research (mac-toolbox v2, 2026-08-27).
# Warns on missing/outdated; NEVER installs or downgrades. Idempotent, read-only.
set -u

MIN_OPENSRC="0.7"
MIN_GITLEAKS="8.30"
MIN_OSV="2.5"
MIN_TRIVY="0.74"       # phase 2 — optional
MIN_SKILLSPECTOR="2"

fail=0

check() { # name min_version version_command
  local name="$1" min="$2"; shift 2
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "MISSING: $name (min $min) — install per docs/tooling-policy.md §Install"
    return 1
  fi
  local ver
  ver="$("$@" 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
  if [ -z "$ver" ]; then
    echo "WARN: $name present but version unparseable"
    return 0
  fi
  # lowest of (min, ver): equals min  => ver >= min => OK; equals ver => outdated
  local lowest
  lowest="$(printf '%s\n%s\n' "$min" "$ver" | sort -V | head -n1)"
  if [ "$lowest" = "$min" ]; then
    echo "OK: $name $ver (>= $min)"
  else
    echo "OUTDATED: $name $ver < min $min — upgrade but never downgrade"
    return 1
  fi
}

check opensrc        "$MIN_OPENSRC"        opensrc --version || fail=1
check gitleaks       "$MIN_GITLEAKS"       gitleaks version || fail=1
check osv-scanner    "$MIN_OSV"            osv-scanner --version || fail=1
# Phase-2 optional tool:
if command -v trivy >/dev/null 2>&1; then
  check trivy "$MIN_TRIVY" trivy --version || fail=1
else
  echo "OPTIONAL: trivy not installed (phase 2) — 'brew install trivy' enables deeper fs scans"
fi
# skillspector prints warnings before its version line; grab any x.y from output
if command -v skillspector >/dev/null 2>&1; then
  sver="$(skillspector --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
  slowest="$(printf '%s\n%s\n' "$MIN_SKILLSPECTOR" "${sver:-0}" | sort -V | head -n1)"
  if [ -n "$sver" ] && [ "$slowest" = "$MIN_SKILLSPECTOR" ]; then
    echo "OK: skillspector $sver (>= $MIN_SKILLSPECTOR)"
  else
    echo "OUTDATED/UNPARSEABLE: skillspector ($sver) — uv tool upgrade skillspector"
    fail=1
  fi
else
  echo "MISSING: skillspector — uv tool install git+https://github.com/NVIDIA/skillspector.git"
  fail=1
fi

exit $fail
