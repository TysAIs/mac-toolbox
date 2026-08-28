<div align="center">

# mac-toolbox

**Give every agent on your Mac the same safe, layered ability to see and operate real apps — plus keep the machine healthy while they work.**

[![CI](https://github.com/TysAIs/mac-toolbox/actions/workflows/ci.yml/badge.svg)](https://github.com/TysAIs/mac-toolbox/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![License](https://img.shields.io/badge/license-MIT-blue)

*Built for [Hermes Agent](https://github.com/nousresearch/hermes-agent), works for any agent platform that uses `SOUL.md` / `SKILL.md` conventions.*

</div>

---

## The problem

AI agents fail at desktop work for two reasons:

1. **No hands or eyes.** They can run terminal commands, but if a task lives inside a GUI — System Settings, an OAuth consent sheet, an upload dialog, any app without a CLI — they're stuck.
2. **Too many overlapping tools.** Once you add GUI automation, agents waste turns picking the *wrong layer* (clicking through menus when one CLI command would do it).

And once they *can* work, they create a third problem nobody plans for:

3. **They leave messes behind.** Dozens of duplicate browser tabs from automation runs, zombie agent processes stuck at 0% CPU for hours, RAM quietly eaten until the whole Mac slows down.

mac-toolbox solves all three: the routing ladder for control, plus hygiene rules and a watchdog that keeps agents from trashing your machine.

## The fix: a routing ladder, stamped into every agent

```
┌─ Task arrives ───────────────────────────────────────────────┐
│                                                              │
│  1. Targeted CLI exists?  ────── yes ──► use it (cheapest)   │
│         │ no                                                 │
│  2. Known AppleScript?    ── yes ──► osascript / mac.script()│
│         │ no                                                 │
│  3. Native-app GUI work?  ── yes ──► macos-harness           │
│         │                        background screenshots,     │
│         │                         PID-targeted input, AX tree│
│  4. Web task?             ── yes ──► your browser automation │
│         │ no                                                 │
│  5. Fallback: full-screen computer-use vision drivers        │
└──────────────────────────────────────────────────────────────┘
```

The ladder lives in **one policy file** (single source of truth). A generator
script stamps a compact ~90-word version into every agent's `SOUL.md` — so your
whole fleet stays perfectly in sync and can never drift:

```
computer-control-policy.md  ──►  stamp script  ──►  SOUL.md (default bot)
      (edit here once)                              SOUL.md (profile A)
                                                    SOUL.md (profile B)
                                                    ...every agent
```

Everything else — detailed skill instructions, recipes — loads on demand
([progressive disclosure](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)),
costing under 100 words of persistent context per agent.

## Quick start

One line (clones + runs the installer):

```bash
git clone https://github.com/TysAIs/mac-toolbox.git && cd mac-toolbox && ./install.sh
```

Or step by step:

```bash
git clone https://github.com/TysAIs/mac-toolbox.git
cd mac-toolbox
SKIP_V2=0 ./install.sh        # SKIP_V2=1 to skip the optional v2 tooling (repo gate, social CLIs)
```

The installer will:

| Step | What happens |
|---|---|
| 1 | Install the [`macos-harness`](https://github.com/browser-use/macos-harness) CLI via `uv` (skipped if present) |
| 2 | Register the skill into `~/.hermes/skills/` |
| 3 | Generate your policy file with this Mac's **auto-detected hardware baseline** |
| 4 | Stamp the ladder into every agent `SOUL.md` (backups made automatically) |

Then grant two macOS permissions when prompted — **Accessibility** and
**Screen & System Audio Recording** — to your terminal / agent-host app.

Verify everything:

```bash
macos-harness doctor                                # expect all true
echo 'print(mac.see("Finder"))' | macos-harness    # expect frame data
```

Restart your Hermes gateway so agents reload souls + skills. Done.

## Changing policy later

Edit **one file**, re-run **one script**:

```bash
$EDITOR ~/.hermes/computer-control-policy.md
~/.hermes/scripts/stamp-computer-control.sh
# optional, for running sessions:
launchctl kickstart -k gui/$(id -u)/ai.hermes.gateway
```

Every agent updates atomically. New profile agents get picked up automatically —
the stamper discovers all `profiles/*/SOUL.md` on its own.

## Resource hygiene: agents that clean up after themselves

The policy file includes mandatory **resource-hygiene rules** that get stamped
into every agent alongside the routing ladder:

- Close every browser tab you opened (≤ 2 per host), verified via CDP before a
  task is "done"
- Reuse existing tabs instead of spawning duplicates
- Kill your own stuck/zombie worker processes — never leave them running
- A finished task that leaves +10 tabs open counts as an incomplete task

And `scripts/resource-watchdog.sh` enforces it mechanically. Run it from cron
(no LLM needed):

```bash
*/30 * * * * ~/.hermes/scripts/resource-watchdog.sh   # empty output = healthy
```

It detects:

| Check | What it catches |
|---|---|
| Zombie agent workers | `chat -q`-style subprocesses alive at 0% CPU for hours |
| Duplicate CDP tabs | e.g. the same console URL opened 25× by repeated runs (measured: 4+ GB RSS) |
| Browser memory bloat | Chromium-family RSS above threshold → audit tabs |
| Stale board heartbeats | opt-in via `WATCHDOG_CARDS_CMD` for your agent-board cards |

Everything is local-only output; point your scheduler at whatever notification
channel you already use.

## Safety model

- Input only goes to **already-running apps**; agents never move your physical
  cursor or steal focus — you can keep working while they do.
- One failed attempt → switch approach. No blind click-spamming, ever.
- Irreversible actions stop at decision boundaries.
- All OS access is gated by macOS TCC permissions **you** grant and can revoke.

## Troubleshooting

<details>
<summary><b>Permission errors ("Screen Recording permission is required")</b></summary>

System Settings → Privacy & Security → grant **Accessibility** and
**Screen & System Audio Recording** to the app that runs your agents (Terminal,
iTerm, or the Hermes desktop app). Then re-run `macos-harness doctor` — every
value should read `true`.
</details>

<details>
<summary><b>Agents don't seem to know about the harness</b></summary>

Skills load at session start. Restart your gateway (or start a fresh session).
Confirm discovery with <code>hermes skills list</code> — you should see
<code>macos-harness</code> as enabled.
</details>

<details>
<summary><b>Install failed midway</b></summary>

Re-run <code>./install.sh</code> — it's fully idempotent. Policy files are written
atomically; souls are backed up (<code>*.bak-stamp-*</code>) before every change;
partial states recover cleanly on the next run. CI runs this exact scenario on
every commit.
</details>

<details>
<summary><b>Does this work on Intel Macs?</b></summary>

Yes. The hardware detector reads real values via <code>sysctl</code>; nothing is
Apple-Silicon-specific.
</details>

## FAQ

**Why not just give agents a computer-use vision driver?**
You can — it's layer 5, the fallback. But full-screen vision clicking is the most
fragile, slowest tool. Agents that ladder up from CLIs → scripts → targeted GUI
primitives finish faster with fewer mistakes.

**Does this send my data anywhere?**
No telemetry in this package. (The upstream harness has opt-out telemetry; this
repo's docs cover disabling it.)

**Windows / Linux?**
Not yet — the harness and permissions model are macOS-native by design.

## Web automation: browser-use + cua-driver (native, open source)

Web tasks route through Hermes-native, open-source tooling — no third-party
closed-source browsers:

- **browser-use** — `browser_exec` tool / `browser-use` CLI. Automates real
  browser sessions (headless or CDP-attached) for page automation, extraction,
  form-filling, and multi-step flows.
- **cua-driver** — `computer_use` tool / `cua-driver` CLI. Full desktop +
  browser control for GUI-level tasks needing pixel/coordinate input (consent
  dialogs, canvas apps, native UI).
- **Brave CDP** — `~/bin/brave-cdp.sh` (port 9222) when a task needs the user's
  live logged-in Brave session. Brave is the user's browser of record; the
  agent never opens a separate closed-source browser.
- **Never** install or route through ego-lite / citrolabs — closed source,
  heavy (48+ processes, 5.5GB RAM observed), and superseded by the stack above.

### Verified against the ego-lite capability set (2026-08-24)

This stack was live-tested to confirm it covers everything ego-lite provided —
isolation, login-state reuse, **auth-flow completion**, and cookie extraction:

| Capability | Verified? |
|---|---|
| Attach to the user's real logged-in Brave session (CDP 9222) | ✅ |
| Drive auth flows (fill login form, click, approve consent) | ✅ `fill_input` → readback verified on x.com/login |
| Tab isolation (agent tabs don't disturb user) | ✅ `Target.createTarget` |
| Extract cookies/tokens for external tools (cookie-backed CLI tools etc.) | ✅ `Network.getAllCookies` |
| Desktop-level GUI (consent dialogs, native UI) | ✅ cua-driver, TCC-gated |

Full evidence: [docs/VERIFIED_REPLACEMENT.md](docs/VERIFIED_REPLACEMENT.md).

Install: both CLIs ship with the Hermes Agent setup (`hermes setup tools`); the
`browser-use` and `computer_use` toolsets are enabled by default in config.

See [TESTS.md](TESTS.md) for the full hard-probe catalog and measured limits,
and [docs/INTEGRATION.md](docs/INTEGRATION.md) for wiring this into **any**
agent harness (Claude Code, OpenAI Assistants, LangChain, custom loops) —
including the three enforcement strategies for resource hygiene and why a
cron is optional, not required.

## v2: repo-security gate + social reach (2026-08-27)

Two new capability lanes, both L0-native CLIs (no GUI/browser layers needed):

### Repo security gate — never run unknown code unvetted

Before any agent clones or installs an unknown repo:

```bash
scripts/repo-intake/gate-clone.sh <repo-url-or-dir>   # pre-clone gate
scripts/repo-intake/gate-run.sh <dir>                  # pre-run gate
```

Combines **gitleaks** (secrets), **osv-scanner** (dependency CVEs),
**NVIDIA SkillSpector** (agent-skill/MCP threats — runs automatically when the
repo contains `SKILL.md`/`mcp.json`), and optional **trivy**. A missing scanner
is a FAIL, never a silent pass. Tools: `npm i -g opensrc`,
`brew install gitleaks osv-scanner`, `uv tool install git+https://github.com/NVIDIA/skillspector.git`.
Full policy + allowlist workflow: [docs/tooling-policy.md](docs/tooling-policy.md).
Skill: `skills/security/repo-security`.

### Social reach — X + Reddit from free cookie-based CLIs

- **twitter-cli** (`skills/social/twitter`) — X read/search/write, no API key.
  Preflight: `source scripts/twitter-env.sh` (loads cookies from
  `~/.mac-toolbox/cookies/twitter.env`, 0600).
- **rdt-cli** (`skills/social/reddit`) — first Reddit capability here; login-cookie,
  7-day TTL.
- **social-doctor** (`scripts/social-doctor.sh`) — one command checks auth health
  for every platform with exact fix commands (`--json` for agents). Never fails on
  optional xurl being absent.
- Onboarding (`scripts/cdp-{twitter,reddit}-login.sh`) automates everything except
  typing your password + 2FA in a visible window — cookies are harvested over CDP
  into 0600 files; values never print, paste, or commit.
- English-platform only by design: no Chinese-platform CLIs (bili-cli, xhs-cli et al.)
  and no agent-reach umbrella dependency.

## Credits

Built on [browser-use/macos-harness](https://github.com/browser-use/macos-harness) (MIT).
Skill packaging and the fleet-policy system designed for [Hermes Agent](https://github.com/nousresearch/hermes-agent).

## License

MIT — see [LICENSE](LICENSE).
