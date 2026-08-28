#!/usr/bin/env bash
# cdp-twitter-login.sh — CDP-assisted X login + cookie harvest.
#
# Splits work by who-can-do-what (mac-toolbox phone-only rule):
#   AUTOMATED: launch dedicated Chromium profile, open x.com login,
#              pre-fill username if provided, harvest auth_token+ct0 cookies
#              after sign-in, write ~/.mac-toolbox/cookies/twitter.env (0600),
#              verify with social-doctor.
#   HUMAN ONLY: the user types their password and 2FA code in the visible window.
#
# Usage: cdp-twitter-login.sh [email-or-username]
# Requires: Google Chrome (or set CHROME_BIN). Uses a DEDICATED profile at
# ~/.mac-toolbox/chromium/twitter so harvested cookies never touch daily browsing.
set -euo pipefail

USER_HINT="${1:-}"
PROF="$HOME/.mac-toolbox/chromium/twitter"
COOKDIR="$HOME/.mac-toolbox/cookies"
COOKIES_ENV="$COOKDIR/twitter.env"
CHROME="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
DEBUG_PORT=9331

mkdir -p "$PROF" "$COOKDIR"

echo "==> Launching dedicated Chromium profile (window will be visible)"
"$CHROME" --user-data-dir="$PROF" --remote-debugging-port=$DEBUG_PORT \
  --no-first-run --no-default-browser-check \
  "https://x.com/i/flow/login" >/dev/null 2>&1 &
CHROME_PID=$!
sleep 4

# Wait for CDP endpoint
for i in $(seq 1 20); do
  curl -s "http://127.0.0.1:$DEBUG_PORT/json/version" >/dev/null && break
  sleep 1
done

if [ -n "$USER_HINT" ]; then
  echo "==> Pre-filling username field via CDP (you still type the password)"
  python3 - "$DEBUG_PORT" "$USER_HINT" <<'PYEOF'
import json, sys, time, urllib.request

port, user = sys.argv[1], sys.argv[2]

def ws_send(ws_url, calls):
    # Minimal CDP client over websocket without external deps:
    # fall back gracefully if `websocket-client` is unavailable.
    try:
        import websocket  # type: ignore
    except ImportError:
        print("SKIP: pip 'websocket-client' not installed; type username manually")
        return
    from urllib.parse import urlparse
    import base64, os, socket, struct, hashlib

    # tiny raw ws client — keep it simple: use websocket-client if present only
    ws = websocket.create_connection(ws_url, timeout=10)
    for i, (method, params) in enumerate(calls):
        ws.send(json.dumps({"id": i + 1, "method": method, "params": params}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == i + 1:
                break
    ws.close()

targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
page = next((t for t in targets if t["type"] == "page"), None)
if page:
    try:
        ws_send(page["webSocketDebuggerUrl"], [
            ("Runtime.evaluate", {
                "expression":
                    "const el=document.querySelector('input[autocomplete=\"username\"],input[name=\"text\"]');"
                    f"if(el){{el.focus();document.execCommand('insertText',false,{json.dumps(user)});}}",
                "returnByValue": True}),
            ("Runtime.evaluate", {"expression":
                "const b=[...document.querySelectorAll('div[role=button]')]"
                ".find(x=>/next|continue/i.test(x.textContent));b&&b.click()", "returnByValue": True}),
        ])
        print("username pre-filled; the user types password + 2FA now")
    except Exception as e:
        print(f"pre-fill skipped ({e}); the user types username+password+2FA")
PYEOF
fi

echo ""
echo "============================================================"
echo " USER (phone-only step): in the opened Chrome window,"
echo " type your X password, then your 2FA code if prompted."
echo " Press ENTER HERE once you are signed in."
echo "============================================================"
read -r

echo "==> Harvesting cookies via CDP Network.getAllCookies"
python3 - "$DEBUG_PORT" "$COOKIES_ENV" <<'PYEOF'
import json, socket, struct, sys, base64, hashlib, os
from urllib.parse import urlparse
import urllib.request

port, out_path = sys.argv[1], sys.argv[2]
targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
page = next((t for t in targets if t["type"] == "page"), None)
assert page, "no page target found"

ws_url = page["webSocketDebuggerUrl"].replace("ws://", "")
hostport, path = ws_url.split("/", 1)
host, port_s = hostport.split(":")
key = base64.b64encode(os.urandom(16)).decode()

s = socket.create_connection((host, int(port_s)))
req = (f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
       f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
s.sendall(req.encode())
s.recv(4096)

def send(obj):
    data = json.dumps(obj).encode()
    header = bytearray([0x81])
    n = len(data)
    mask = os.urandom(4)
    if n < 126: header.append(0x80 | n)
    elif n < 65536: header += bytes([0x80 | 126]) + struct.pack(">H", n)
    else: header += bytes([0x80 | 127]) + struct.pack(">Q", n)
    header += mask
    s.sendall(bytes(header) + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def recv_exact(n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        assert chunk, "socket closed"
        buf += chunk
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

cookies = {c["name"]: c["value"] for c in m["result"]["cookies"]
           if "x.com" in c.get("domain", "") or ".twitter.com" in c.get("domain", "")}
auth, ct0 = cookies.get("auth_token"), cookies.get("ct0")
assert auth and ct0, f"missing cookies post-login (got: {sorted(cookies)})"

with open(out_path, "w") as f:
    f.write(f"TWITTER_AUTH_TOKEN={auth}\nTWITTER_CT0={ct0}\n")
os.chmod(out_path, 0o600)
print(f"wrote {out_path} (values withheld)")
PYEOF

osascript -e "tell application \"Google Chrome\" to quit" >/dev/null 2>&1 || kill $CHROME_PID 2>/dev/null || true
echo "==> Verifying with doctor:"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/social-doctor.sh" || true
