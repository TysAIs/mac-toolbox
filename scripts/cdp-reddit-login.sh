#!/usr/bin/env bash
# cdp-reddit-login.sh — CDP-assisted Reddit login + cookie handoff to rdt-cli.
#
# Split of work (phone-only rule):
#   AUTOMATED: open dedicated Chromium profile at reddit.com/login, harvest
#              cookies post-sign-in, stage ~/.mac-toolbox/cookies/reddit.env,
#              run `rdt login` against the CDP profile (auto-extract), verify
#              with social-doctor.
#   HUMAN ONLY: the user types their Reddit password + 2FA code in the window.
#
# Usage: cdp-reddit-login.sh
# Timebox note (R2 §8): rdt-cli's headless cookie env-var name is
# doctor-documented only; we therefore prefer letting `rdt login` extract from
# the dedicated Chromium profile directly. If that fails, the staged cookie
# string is written for manual mapping per `rdt status --json` error text.
set -euo pipefail

PROF="$HOME/.mac-toolbox/chromium/reddit"
COOKDIR="$HOME/.mac-toolbox/cookies"
CHROME="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
DEBUG_PORT=9332

mkdir -p "$PROF" "$COOKDIR"

echo "==> Launching dedicated Chromium profile (visible window)"
"$CHROME" --user-data-dir="$PROF" --remote-debugging-port=$DEBUG_PORT \
  --no-first-run --no-default-browser-check \
  "https://www.reddit.com/login" >/dev/null 2>&1 &
CHROME_PID=$!
for i in $(seq 1 20); do curl -s "http://127.0.0.1:$DEBUG_PORT/json/version" >/dev/null && break; sleep 1; done

echo ""
echo "============================================================"
echo " USER (phone-only step): in the opened Chrome window,"
echo " type your Reddit username, password, and 2FA code if asked."
echo " Press ENTER HERE once you are signed in."
echo "============================================================"
read -r

echo "==> Harvesting reddit.com cookies into staging file"
python3 - "$DEBUG_PORT" "$COOKDIR/reddit.env" <<'PYEOF'
import json, os, socket, struct, sys, base64, urllib.request

port, out_path = sys.argv[1], sys.argv[2]
targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
page = next(t for t in targets if t["type"] == "page")
ws_url = page["webSocketDebuggerUrl"].replace("ws://", "")
hostport, path = ws_url.split("/", 1)
host, port_s = hostport.split(":")
key = base64.b64encode(os.urandom(16)).decode()

s = socket.create_connection((host, int(port_s)))
s.sendall((f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
s.recv(4096)

def send(obj):
    data = json.dumps(obj).encode()
    header = bytearray([0x81]); n = len(data); mask = os.urandom(4)
    if n < 126: header.append(0x80 | n)
    elif n < 65536: header += bytes([0x80 | 126]) + struct.pack(">H", n)
    else: header += bytes([0x80 | 127]) + struct.pack(">Q", n)
    header += mask
    s.sendall(bytes(header) + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def recv_exact(n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf)); assert chunk; buf += chunk
    return buf

def recv():
    b1, b2 = recv_exact(2)
    n = b2 & 0x7F
    if n == 126: n = struct.unpack(">H", recv_exact(2))[0]
    elif n == 127: n = struct.unpack(">Q", recv_exact(8))[0]
    return json.loads(recv_exact(n).decode())

send({"id": 1, "method": "Network.getAllCookies"})
while True:
    m = recv()
    if m.get("id") == 1: break

cookies = [c for c in m["result"]["cookies"] if "reddit.com" in c.get("domain", "")]
assert cookies, "no reddit cookies found — was sign-in completed?"
jar = "; ".join(f"{c['name']}={c['value']}" for c in cookies)

with open(out_path, "w") as f:
    f.write(f"# staged cookie jar for rdt-cli headless fallback\n")
    f.write(f"REDDIT_COOKIE_STR='{jar}'\n")
os.chmod(out_path, 0o600)
print(f"staged {len(cookies)} cookies -> {out_path} (values withheld)")
PYEOF

osascript -e "tell application \"Google Chrome\" to quit" >/dev/null 2>&1 || kill $CHROME_PID 2>/dev/null || true

echo "==> Trying 'rdt login' auto-extract (primary path)"
if command -v rdt >/dev/null 2>&1 && rdt login <<<"" 2>/dev/null; then
  echo "rdt login completed extraction"
else
  # Point rdt's browser detection at the dedicated profile's cookies by
  # falling back to documented doctor guidance:
  echo "'rdt login' needs an interactive browser pick — run it manually against"
  echo "the dedicated profile at $PROF, or map REDDIT_COOKIE_STR per the"
  echo "headless fallback printed by 'rdt status --json'."
  rdt status --json || true
fi

echo "==> Verifying with doctor:"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/social-doctor.sh" || true
