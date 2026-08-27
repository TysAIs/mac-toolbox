#!/bin/bash
# install.sh — set up the computer-control stack for Hermes Agent on this Mac.
set -euo pipefail
DEST="${HERMES_HOME:-$HOME/.hermes}"
SRC="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 1/4 Installing macos-harness CLI (uv)"
command -v macos-harness >/dev/null || {
  command -v uv >/dev/null || brew install uv
  uv tool install --python 3.12 macos-harness
}

echo "==> 2/4 Copying skills into $DEST/skills/"
for skill_src in "$SRC"/skills/*/*; do
  [ -d "$skill_src" ] || continue
  category=$(basename "$(dirname "$skill_src")")
  skill=$(basename "$skill_src")
  mkdir -p "$DEST/skills/$category"
  rm -rf "$DEST/skills/$category/$skill"
  cp -R "$skill_src" "$DEST/skills/$category/$skill"
  echo "    installed $category/$skill"
done

echo "==> 3/6 Installing helper scripts into $DEST/scripts/"
mkdir -p "$DEST/scripts" "$DEST/scripts/repo-intake"
for s in "$SRC"/scripts/*.sh "$SRC"/scripts/*.py; do
  [ -f "$s" ] || continue
  cp "$s" "$DEST/scripts/"
  chmod +x "$DEST/scripts/$(basename "$s")"
done
for s in "$SRC"/scripts/repo-intake/*.sh; do
  [ -f "$s" ] || continue
  cp "$s" "$DEST/scripts/repo-intake/"
  chmod +x "$DEST/scripts/repo-intake/$(basename "$s")"
done

echo "==> 4/6 Optional: v2 security + social tooling (skip with SKIP_V2=1)"
if [ "${SKIP_V2:-0}" != "1" ]; then
  command -v npm >/dev/null && { command -v opensrc >/dev/null || npm install -g opensrc || true; }
  for b in gitleaks osv-scanner trivy; do
    command -v "$b" >/dev/null || brew install "$b" || true
  done
  command -v uv >/dev/null && {
    command -v twitter >/dev/null || uv tool install twitter-cli || true
    command -v rdt >/dev/null || uv tool install rdt-cli || true
    command -v skillspector >/dev/null || uv tool install git+https://github.com/NVIDIA/skillspector.git || true
  }
  mkdir -p "$HOME/.mac-toolbox/cookies"
  chmod 700 "$HOME/.mac-toolbox/cookies" 2>/dev/null || true
else
  echo "    skipped"
fi

echo "==> 5/6 Generating policy file with detected hardware"
if [ ! -s "$DEST/computer-control-policy.md" ]; then
  "$SRC/scripts/detect-hardware.sh" > "$TMP/hardware.md"
  # Splice hardware block over the {{HARDWARE_BASELINE}} marker line.
  # awk getline-from-file: fully portable, no escaping pitfalls.
  awk -v hwfile="$TMP/hardware.md" '
    /\{\{HARDWARE_BASELINE\}\}/ { while ((getline line < hwfile) > 0) print line; next }
    { print }
  ' "$SRC/computer-control-policy.template.md" > "$TMP/policy.md"
  [ -s "$TMP/policy.md" ] || { echo "ERROR: policy generation produced an empty file" >&2; exit 1; }
  grep -q '^Version:' "$TMP/policy.md" || { echo "ERROR: generated policy has no Version line" >&2; exit 1; }
  mkdir -p "$DEST"
  mv "$TMP/policy.md" "$DEST/computer-control-policy.md"   # atomic: no zombie empty files
else
  echo "    policy exists and is non-empty — leaving untouched"
fi

echo "==> 6/6 Stamping ladder + hygiene rules into all agent SOUL.md files"
"$SRC/scripts/stamp-computer-control.sh" "$DEST"

cat <<'EOF'

Done. Remaining manual steps:
  1. System Settings -> Privacy & Security -> grant Accessibility and
     Screen & System Audio Recording to your terminal / agent host app.
  2. Verify:        macos-harness doctor          (expect all true)
  3. Live test:     echo 'print(mac.see("Finder"))' | macos-harness
  4. Optional: schedule resource hygiene checks (no LLM needed):
     */30 * * * * $DEST/scripts/resource-watchdog.sh
  5. Restart your Hermes gateway so agents reload souls + skills.
  6. Social auth (twitter-cli / rdt-cli) needs one login per platform:
     run ~/.hermes/scripts/cdp-twitter-login.sh (and the reddit variant).
EOF
