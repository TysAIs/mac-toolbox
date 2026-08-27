# Integrating mac-toolbox with ANY agent harness

mac-toolbox is deliberately platform-agnostic. It ships three artifacts, and
each one has a known integration point in every major harness:

| Artifact | What it is | How agents consume it |
|---|---|---|
| `computer-control-policy.template.md` | The routing ladder + resource-hygiene rules (single source of truth) | Stamped (compact) or loaded (full) into the agent's system prompt / persona file |
| `skills/apple/macos-harness/` | A SKILL.md in the open [Agent Skills](https://agentskills.io) format (`SKILL.md` + frontmatter) | Drop into any skills directory; progressive disclosure loads it only when needed |
| `scripts/resource-watchdog.sh` | Pure-bash leak detector (no LLM, no deps beyond bash + curl + python3) | Run by ANY scheduler: cron, systemd timers, launchd, GitHub Actions, CI jobs — or as a tool the agent calls itself |

## The three integration patterns

### Pattern 1 — SOUL.md / persona stamping (Hermes Agent, custom agents)

The default flow. A compact ~140-word version of the policy is injected into
every agent's persona file so ALL agents know the ladder and hygiene rules
without loading full skills:

```bash
git clone https://github.com/TysAIs/mac-toolbox.git && cd mac-toolbox
./install.sh                       # Hermes layout ($HOME/.hermes)
```

For non-Hermes layouts, do the two steps manually:

```bash
# 1. Policy single-source-of-truth (edit THIS, never the stamped copies):
cp computer-control-policy.template.md /your/agent/home/computer-control-policy.md

# 2. Stamp the compact block into every persona/system-prompt file:
./scripts/stamp-computer-control.sh /your/agent/home
```

The stamper discovers **every** `SOUL.md` under `<home>/profiles/*/SOUL.md`
plus `<home>/SOUL.md`, backs each up before editing, strips any previous
stamped block (including partially-truncated ones), and is idempotent — safe
to re-run on every deploy.

If your harness uses a different filename (e.g. `system.md`, `PERSONA.md`,
Claude Code's `CLAUDE.md`, OpenAI Assistants "instructions"), either symlink
it as `SOUL.md` for the stamper, or copy the stamped block from an existing
file — it is fully self-contained between the
`<!-- BEGIN computer-control ... -->` markers.

### Pattern 2 — Agent Skills (Claude Code, Claude.ai, any skills-compatible harness)

mac-toolbox ships its GUI-automation knowledge as a standard skill:

```bash
# Claude Code
mkdir -p ~/.claude/skills/apple
cp -R mac-toolbox/skills/apple/macos-harness ~/.claude/skills/apple/
```

The skill uses only frontmatter fields defined by the Agent Skills spec
(`name`, `description`, plus optional metadata), so it ports cleanly to any
harness that reads SKILL.md files. Agents load the ~90-word description at
startup and pull the full instructions only when a GUI task actually appears.

### Pattern 3 — API-only agents (OpenAI Assistants SDK, LangChain, custom loops)

For agents that have no filesystem persona, paste the stamped policy block
directly into the system prompt:

```python
from pathlib import Path
import re

soul = Path("path/to/SOUL.md").read_text()
ladder = re.search(
    r"<!-- BEGIN computer-control.*?-->(.*?)<!-- END computer-control -->",
    soul, re.S,
).group(1)

assistant = client.beta.assistants.create(
    name="MyMacAgent",
    instructions=BASE_PROMPT + ladder,   # ~140 words of context
    tools=[...],                          # your exec/computer tools
)
```

Word-count matters: the compact stamp is designed to cost <150 tokens of
persistent context while the full skill (~1 page) loads only when needed.

## Making it as efficient as possible

Efficiency here means two different budgets. Keep them separate:

**Context budget (tokens).** Never put the whole policy in the prompt. Use the
three-tier load: the compact stamped ladder (~150 tokens, always present) →
the skill description (~50 tokens) → the full SKILL.md (loaded on first GUI
task). That keeps per-agent overhead near zero until real work happens.

**Machine budget (RAM/CPU/tabs).** This is where leaks come from, and there
are exactly three sane enforcement strategies. Pick based on how much you
trust your agents:

| Strategy | Mechanism | Latency | Best for |
|---|---|---|---|
| **Policy-first** (default) | Rules live in the agent's own prompt; agent closes tabs/kills workers itself as part of task completion | Zero infra; enforcement = agent discipline | Trusted agents, solo setups |
| **Scheduler sweep** | Watchdog runs periodically, reports/kills leaks | Detects within minutes after the fact | Sleep-safe automation, fleets |
| **Wrapper-gate** | Harness intercepts tool calls: tab-tracking wrapper auto-closes what a session opened; process supervisor reaps children | Immediate, zero trust needed | Untrusted code, long-lived sessions |

**Does it have to be cron? No.** The watchdog is just a script — wire it into
whatever your environment already runs:

```bash
# launchd (macOS-native; survives reboot, runs missed jobs):
launchctl submit -l com.mac-toolbox.watchdog \
  --program-arguments "$HOME/.hermes/scripts/resource-watchdog.sh" \
  --start-interval 1800

# systemd timer (Linux/macOS with systemd):
#   OnUnitActiveSec=30m with a companion service file

# GitHub Actions (headless CI runners):
#   schedule: [{cron: '*/30 * * * *'}]

# As an agent tool (LLM calls it before "task done" self-checks):
$HOME/.hermes/scripts/resource-watchdog.sh && echo "hygiene verified"
```

Or skip periodic sweeps entirely if your harness supports hooks: run the
watchdog **once inside the post-task hook** instead of polling all day
(Hermes "Stop" hook, Claude Code `PostToolUse`, LangGraph node epilogue).
Event-driven beats scheduled on both cost and latency — the machine checks
only when work finishes.

The watchdog itself is frugal by design: ~40 ms runtime, zero network beyond a
local CDP probe, silent (empty stdout) when healthy, exit 0 always.

## Non-goals (why this stays small)

- No daemon, no background server, no config database. Two scripts + docs.
- No cross-platform claims yet — the permission model (TCC, accessibility)
  is macOS-specific by design.
- No telemetry.
