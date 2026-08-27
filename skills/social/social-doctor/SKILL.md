---
name: social-doctor
description: "One-command auth/cookie health check for the social CLIs (twitter-cli, rdt-cli, optional xurl): per-platform L0/L1/L2 status with fix commands. Use WHEN an X or Reddit call fails with auth errors, before assuming a platform outage, or during onboarding verification."
version: 0.1.0
author: mac-toolbox v2 (TysAIs)
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [social, diagnostics, health-check]
prerequisites:
  commands: [bash]
---

# Social Doctor

```bash
scripts/social-doctor.sh          # human: one line per platform + fix
scripts/social-doctor.sh --json   # machine: [{"platform","check_level","ok","fix"}]
```

Checks (English-only output; never prints cookie values):

- **twitter**: L0 binary · L1 cookie env (`TWITTER_AUTH_TOKEN`+`TWITTER_CT0`
  present in `~/.mac-toolbox/cookies/twitter.env`) · L2 live probe
  (`twitter search "test" --max 1`, 20s timeout).
- **reddit**: L0 binary · L1 `rdt status --json` ok-flag + credential age
  (warn >6d, fail >7d TTL).
- **xurl** (optional official-API lane): missing = SKIP, never FAIL.

Exit codes: 0 all OK · 1 any FAIL.

Mandates:

1. Run the doctor BEFORE concluding any platform is down — most failures are
   stale cookies, not outages.
2. Act on the printed `fix:` lines; they are exact commands.
3. The doctor is read-only and never triggers logins. Login steps:
   `scripts/cdp-twitter-login.sh` / `cdp-reddit-login.sh` — everything is
   automated EXCEPT Tyler typing his password + 2FA code in the visible
   window (phone-only rule). No cookie pasting, no token copying, ever.
4. Onboarding shortcut: if Tyler's daily browser already has valid sessions,
   `rdt login` and browser auto-extract need zero manual steps; record which
   browser profile was used in `~/.mac-toolbox/state/auth.json`.
