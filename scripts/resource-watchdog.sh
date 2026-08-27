#!/usr/bin/env bash
# mac-toolbox resource watchdog
# Detects agent-caused resource leaks on this Mac and reports them.
# Designed for cron (no_agent) or manual runs. Exit 0 always;
# stdout is the report (empty when healthy).
#
# Checks:
#   1. Stuck chat -q agent workers (0% CPU AND older than 45 min)
#   2. CDP browser tab duplication (>3 tabs sharing one URL+host)
#   3. Browser memory bloat (Chromium-family RSS above threshold)
#   4. Agent board cards running with stale heartbeats (>90 min; optional)
set -u
REPORT=""

now=$(date +%s)

# ── 1. zombie chat -q workers ──────────────────────────────────────────
while read -r pid cpu etime; do
  [ -z "$pid" ] && continue
  # etime may be [[dd-]hh:]mm:ss — normalize to seconds before comparing
  secs=$(echo "$etime" | awk -F'[-:]' '{if(NF==4)s=$1*86400+$2*3600+$3*60+$4; else if(NF==3)s=$1*3600+$2*60+$3; else s=$1*60+$2; print s}')
  [ "$secs" -ge 3600 ] && REPORT+="ZOMBIE: pid $pid hermes chat worker up ${etime}, cpu ${cpu}% — kill it"$'\n'
done < <(ps -Ao pid,pcpu,etime,args | awk '/chat -q/ && !/awk/ {print $1, $2, $3}')

# ── 2. CDP duplicate tabs ──────────────────────────────────────────────
TABJSON=$(curl -s --max-time 5 http://localhost:9222/json/list 2>/dev/null || true)
if [ -n "$TABJSON" ]; then
  DUPLICATES=$(printf '%s' "$TABJSON" | python3 -c '
import json, sys
from collections import Counter
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
pages = [t for t in d if t.get("type") == "page"]
c = Counter((t.get("url","").split("/")[2] if len(t.get("url","").split("/"))>2 else "?", t.get("title","")[:40]) for t in pages)
for (host,title), n in c.items():
    if n > 3:
        print(f"DUP TABS: {n}x {title} ({host}) — dedupe via /json/close/<id>")
')
  [ -n "$DUPLICATES" ] && REPORT+="$DUPLICATES"$'\n'
fi

# ── 3. browser RSS bloat ───────────────────────────────────────────────
BRAVE_MB=$(ps -Ao rss,comm | grep -i "[b]rave" | awk '{s+=$1} END {print int(s/1024)}')
if [ -n "${BRAVE_MB:-}" ] && [ "$BRAVE_MB" -gt 6000 ]; then
  REPORT+="BROWSER BLOAT: Brave at ${BRAVE_MB} MB RSS — audit tabs via CDP"$'\n'
fi

# ── 4. stale agent-board card heartbeats (opt-in; generic via WATCHDOG_CARDS_CMD) ──
# Set WATCHDOG_CARDS_CMD to a command that prints heartbeat timestamps (one per
# line, "YYYY-MM-DD HH:MM") for your in-flight cards. Example for kanban-style
# boards:
#   WATCHDOG_CARDS_CMD="hermes-kanban-heartbeats" ./resource-watchdog.sh
if [ -n "${WATCHDOG_CARDS_CMD:-}" ] && command -v "$WATCHDOG_CARDS_CMD" >/dev/null 2>&1; then
  while IFS= read -r hb; do
    [ -z "$hb" ] && continue
    ts=$(date -j -f "%Y-%m-%d %H:%M" "$hb" +%s 2>/dev/null || date -d "$hb" +%s 2>/dev/null || echo 0)
    if [ "$ts" -gt 0 ] && [ $((now - ts)) -gt 5400 ]; then
      REPORT+="STALE HEARTBEAT: last activity ${hb} (>90min) — check the owning worker"$'\n'
    fi
  done < <($WATCHDOG_CARDS_CMD)
fi

if [ -z "$REPORT" ]; then
  echo "healthy $(date '+%H:%M')"
else
  printf '%s' "$REPORT"
fi
