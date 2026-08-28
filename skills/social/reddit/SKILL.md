---
name: reddit
description: "Reddit read, search, subreddit browse, post/comment read, vote, save, subscribe via free cookie-based rdt-cli — the first Reddit capability on this machine. Use WHEN reading/searching/acting on Reddit; check rdt status ok first."
version: 0.1.0
author: mac-toolbox v2 (TysAIs)
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [social, reddit, cli]
prerequisites:
  commands: [rdt]
---

# Reddit — rdt-cli

Auth contract: login-cookie only. Reddit has NO zero-config path (anonymous
.json endpoints are blocked). Before use:

```bash
rdt status --json        # must show "ok": true
```

Cookies persist at `~/.config/rdt-cli/credential.json` (0600), 7-day TTL.
`(Re)harvest with rdt login` (auto-extracts from your browser) or
`scripts/cdp-reddit-login.sh`. If the credential is older than ~6 days, run
the doctor first.

## Read/search cheat-sheet

```bash
rdt feed --subs-only                 # subscriptions feed
rdt popular --full-text              # /r/popular ; 'rdt all' for /r/all
rdt sub python -s top -t week        # subreddit browse (sort/time)
rdt sub-info python
rdt user spez / user-posts spez / user-comments spez
rdt read 1abc123 [--expand-more]     # post + comment tree
rdt show 3                           # item #3 of last list (short index)
rdt search "python async" [-r programming]
rdt export "python tips" -n 100 -o out.csv   # CSV/JSON export
rdt saved / rdt upvoted
```

## Write/list cheat-sheet

```bash
rdt upvote 3 / downvote 3            # index or ID
rdt save 3 / unsave 3
rdt subscribe python / unsubscribe python
rdt comment 3 "Great post!"
```

## Agent rules

- Envelope is `{ok, schema_version, data|error}`; exit code 1 on API errors —
  check exit code before trusting `ok`.
- Prefer `--json`/`--yaml`; `--compact` saves tokens. Non-TTY defaults to YAML.
- Pitfalls: "database is locked" → close the browser, retry. "Session expired"
  → `rdt logout && rdt login`. Requests are slow by design (~1s jitter) — not
  a hang. Server-IP bans → set standard `HTTPS_PROXY` env (not expected here).
- Any failure → run `scripts/social-doctor.sh` before assuming an outage.

Maintenance note (R2 spec §2.2): plain `uv tool install rdt-cli` (PyPI 0.4.1)
is canonical for reproducibility. A git-pinned variant exists upstream
(0.4.2 @ 5e4fb37) but do NOT fuse to a SHA by default — a stale pin breaks
`uv tool upgrade`.

Upstream: https://github.com/public-clis/rdt-cli (SCHEMA.md linked, not vendored).
