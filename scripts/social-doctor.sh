#!/usr/bin/env bash
# social-doctor.sh — one-command health check for adopted social CLIs
# (twitter-cli, rdt-cli; optional xurl). Modeled on Agent-Reach's doctor but
# implemented locally: English-only, adopted platforms only, no agent-reach dep.
#
# Contract (R2 spec §5.3):
#   - L0 binary present → L1 env/credential present → L2 live probe
#   - xurl missing = SKIP (never FAIL)
#   - Never prints cookie values. Read-only: prescribes fixes, runs no logins.
#   - Exit: 0 all OK · 1 any FAIL
#   - --json emits [{"platform","check_level","ok","fix"}]
set -u

LOG="$(mktemp)"   # TSV lines: platform \t level \t ok|false \t fix
trap 'rm -f "$LOG"' EXIT

record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$LOG"; }
badge() { case "$1" in ok) echo "✅";; warn) echo "⚠️";; fail) echo "❌";; skip) echo "⏭";; esac; }
perl_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }  # macOS has no GNU timeout

# ------------------------------------------------ twitter-cli ----------------
if ! command -v twitter >/dev/null 2>&1; then
  record twitter L0 false "uv tool install twitter-cli"
  echo "$(badge fail) twitter   FAIL L0 binary missing — fix: uv tool install twitter-cli"
else
  ENVF="$HOME/.mac-toolbox/cookies/twitter.env"
  if [ -f "$ENVF" ] && grep -q '^TWITTER_AUTH_TOKEN=..' "$ENVF" 2>/dev/null \
     && grep -q '^TWITTER_CT0=..' "$ENVF" 2>/dev/null; then
    set -a; . "$ENVF"; set +a
    probe="$(mktemp)"
    if perl_timeout 20 twitter search "test" --max 1 --compact >"$probe" 2>&1; then
      record twitter L2 true "none"
      echo "$(badge ok) twitter   OK   L2 live probe passed (search --max 1)"
    else
      err="$(head -c 200 "$probe" | tr '\n' ' ')"
      case "$err" in
        *not_authenticated*|*401*) fix="cookies stale/absent — re-run scripts/cdp-twitter-login.sh or re-extract from browser" ;;
        *rate_limited*|*429*)      fix="rate-limited — wait, keep queries at --max 20" ;;
        *not_found*|*404*)         fix="queryId rotation quirk — retry once; else uv tool upgrade twitter-cli" ;;
        *)                         fix="probe error: $err" ;;
      esac
      record twitter L2 false "$fix"
      echo "$(badge warn) twitter   WARN L2 probe failed — fix: $fix"
    fi
    rm -f "$probe"
    unset TWITTER_AUTH_TOKEN TWITTER_CT0
  else
    record twitter L1 false "no cookie jar at ~/.mac-toolbox/cookies/twitter.env — run scripts/cdp-twitter-login.sh"
    echo "$(badge fail) twitter   FAIL L1 env missing — fix: run scripts/cdp-twitter-login.sh"
  fi
fi

# ------------------------------------------------ rdt-cli --------------------
if ! command -v rdt >/dev/null 2>&1; then
  record reddit L0 false "uv tool install rdt-cli"
  echo "$(badge fail) reddit    FAIL L0 binary missing — fix: uv tool install rdt-cli"
else
  cred="$HOME/.config/rdt-cli/credential.json"
  # rdt status can hang indefinitely when browser_cookie3 blocks on a macOS
  # Keychain prompt for "Chrome Safe Storage" (no GUI answer => stuck poll).
  # Hard-cap the probe; treat a timeout as auth-invalid with a clear fix.
  status_json="$(perl_timeout 25 rdt status --json 2>/dev/null || true)"
  rc_rdt=$?
  if [ -z "$status_json" ]; then
    record reddit L1 false "rdt status blocked/timed out (macOS Keychain prompt for Chrome Safe Storage, or no login). Unlock Keychain / click Always Allow, or run 'rdt login' in an interactive terminal"
    echo "$(badge fail) reddit    FAIL L1 status probe timed out — fix: unlock Keychain ('Always Allow' on Chrome Safe Storage) or run rdt login interactively"
  elif printf '%s' "$status_json" | python3 -c 'import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get("ok") else 1)' 2>/dev/null; then
    age_note=""
    if [ -f "$cred" ]; then
      ctime="$(stat -f %m "$cred" 2>/dev/null || echo 0)"
      days=$(( ($(date +%s) - ctime) / 86400 ))
      age_note=", credential ${days}d old"
      if [ "$days" -gt 7 ]; then
        record reddit L1 false "rdt logout && rdt login (credential ${days}d old, TTL expired)"
        echo "$(badge fail) reddit    FAIL L1 credential ${days}d old (>7d TTL) — fix: rdt logout && rdt login"
        age_note=""
      elif [ "$days" -ge 6 ]; then
        record reddit L1 true "proactive refresh soon (rdt logout && rdt login)"
        echo "$(badge warn) reddit    WARN L1 ok, credential ${days}d old (7d TTL nearing)"
        age_note=""
      else
        record reddit L1 true "none"
        echo "$(badge ok) reddit    OK   L1 status ok=true${age_note}"
        age_note=""
      fi
    else
      record reddit L1 true "none"
      echo "$(badge ok) reddit    OK   L1 status ok=true (credential age unreadable)"
    fi
  else
    record reddit L1 false "run 'rdt status --json' to see the missing field; then rdt login (auto-extracts from your browser)"
    echo "$(badge fail) reddit    FAIL L1 auth invalid — fix: rdt login"
  fi
fi

# ------------------------------------------------ xurl (optional) ------------
if command -v xurl >/dev/null 2>&1; then
  record xurl L0 true "none"
  echo "$(badge ok) xurl      OK   installed (official-API lane — see Hermes skill social-media/xurl)"
else
  record xurl L0 true "install only if DMs/media-upload/raw-v2 needed"
  echo "$(badge skip) xurl      SKIP not installed (optional lane; doctor never fails on xurl)"
fi

# ------------------------------------------------ aggregate / output ---------
if [ "${1:-}" = "--json" ]; then
  python3 "$(dirname "$0")/doctor-json.py" < "$LOG"
fi

fail=0
while IFS=$'\t' read -r _plat _lev ok _fix; do
  [ "$ok" = "true" ] || fail=1
done < "$LOG"

exit $fail
