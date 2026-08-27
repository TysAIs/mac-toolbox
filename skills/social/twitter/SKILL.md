---
name: twitter
description: "X/Twitter read, search, timeline, user lookup, post, reply, quote, delete, like, retweet, bookmark via the free cookie-based twitter-cli. Use WHEN reading/searching/posting on X without paid API — requires cookie env preflight first."
version: 0.1.0
author: mac-toolbox v2 (TysAIs)
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [social, twitter, x, cli]
prerequisites:
  commands: [twitter]
---

# Twitter (X) — twitter-cli

Auth contract: cookie-only, no OAuth, no API key. Before ANY `twitter`
command run:

```bash
source ~/.hermes/scripts/twitter-env.sh   # loads TWITTER_AUTH_TOKEN + TWITTER_CT0
```

(wrapped automatically by `scripts/social-doctor.sh` preflight). Cookie jar:
`~/.mac-toolbox/cookies/twitter.env` (0600), populated by
`scripts/cdp-twitter-login.sh` — Tyler types ONLY password + 2FA; everything
else is automated.

xurl is a separate official-API lane (DMs, media upload, raw v2) — do not use
it for normal reads/posts and never double-install it from this repo.

## Read cheat-sheet

```bash
twitter feed -t following --max 20        # home/following timeline
twitter search "QUERY" -n 20 --json       # also -t Top|Latest|Photos|Videos,
                                          # --from @user, --lang en, --since YYYY-MM-DD
twitter tweet 1234567890                  # tweet + replies (URL ok)
twitter thread <id>                       # full thread
twitter user @handle                      # profile
twitter user-posts @handle --max 20
twitter likes @handle --max 30            # own likes only (X privacy, Jun 2024)
twitter followers @handle --max 50
twitter bookmarks                         # own bookmarks
twitter article <id> --markdown           # X Article -> markdown (unique here)
twitter list <list-id>
twitter show 2 --json                     # item #2 of last list (short index)
```

## Write cheat-sheet

```bash
twitter post "text" [-i img.png ...]      # up to 4 images
twitter reply <tweet-id> "text"
twitter quote <tweet-id> "text" -i img.png
twitter delete <tweet-id>
twitter like/unlike/retweet/unretweet/bookmark/unbookmark <id>
twitter follow @handle
```

## Agent rules

- Output: prefer `--yaml` for agents; `--json` when scripting; `-c/--compact`
  to save tokens. Never parse the rich table output.
- Cap pulls: `--max 20`, not hundreds.
- Structured auth errors: `not_authenticated`, `not_found`, `rate_limited`,
  `api_error`. On any failure run `scripts/social-doctor.sh` FIRST before
  assuming an outage.
- Error 404 = upstream queryId rotation → retry once, then
  `uv tool upgrade twitter-cli`.
- First browser-cookie extraction may pop a macOS Keychain prompt → click
  "Always Allow".

Upstream: https://github.com/public-clis/twitter-cli (its SKILL.md/SCHEMA.md
are linked, not vendored).
