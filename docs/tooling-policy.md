# Tooling policy — repo intake + social reach (mac-toolbox v2)

Version: 2026-08-27 · Scope: every agent operating on this Mac.

## 1. Repo intake gate (MANDATORY)

Before any agent on this Mac `git clone`s an unknown repo, or runs
`npm install` / `uv add` / `uv run` / `npm run` inside one:

```bash
scripts/repo-intake/gate-clone.sh <repo-url-or-dir>   # pre-clone/pre-install
scripts/repo-intake/gate-run.sh <dir>                 # post-install, pre-run
```

- A missing scanner binary is a FAIL (exit 2), never a silent pass. Fix the
  environment first with the Install commands below.
- WARN (exit 1) means findings exist — read the reports, decide consciously,
  and only then proceed. `--strict` upgrades WARN to FAIL.
- Known-good repos can be allowlisted in this file's §4 as they accumulate
  clean fingerprints.
- Update checks: `scripts/repo-intake/check-versions.sh` warns on drift,
  never downgrades.

## 2. Tool inventory (verified live 2026-08-27)

| Tool | Min version | Install | Purpose |
|---|---|---|---|
| opensrc | 0.7 | `npm install -g opensrc` | package/repo source fetch for agents |
| gitleaks | 8.30 | `brew install gitleaks` | secret detection |
| osv-scanner | 2.5 | `brew install osv-scanner` | dependency CVEs (OSV.dev) |
| trivy | 0.74 | `brew install trivy` | optional phase-2 fs/IaC scan |
| skillspector | 2.x | `uv tool install git+https://github.com/NVIDIA/skillspector.git` | agent-skill/MCP threat scan |

Install rules:

1. skillspector is **git+uv only** — it is NOT on PyPI/npm; never copy a PyPI
   line from anywhere else into these scripts.
2. `~/.opensrc/` is per-user cache; never commit its contents to any repo.
3. Scanner defaults are keyless (`skillspector --no-llm`). LLM mode is opt-in
   via `SKILLSPECTOR_PROVIDER`.

## 3. Social reach lanes (adopted R2 decisions)

- **X default lane**: twitter-cli (free cookie auth). Preflight:
  `source ~/.hermes/scripts/twitter-env.sh`.
- **Reddit lane**: rdt-cli (login cookie, 7-day TTL). Preflight:
  `rdt status --json` ok-flag.
- **X official-API lane**: xurl stays registered-but-not-installed (Hermes
  skill `social-media/xurl`) for DMs / media upload / raw v2 only. Do NOT
  double-install xurl from mac-toolbox.
- **Health**: `scripts/social-doctor.sh` before assuming any platform outage;
  act on its `fix:` lines.
- **Secrets**: cookie jars under `~/.mac-toolbox/cookies/` (0700, values
  0600). Never print, paste, or commit cookie values. Login automation may
  pre-fill usernames and harvest cookies; ONLY the human types passwords and
  2FA codes.
- **Chinese platforms**: zero adoption by design (bili-cli, xhs-cli,
  xiaoyuzhou, xueqiu, v2ex modules excluded from mac-toolbox entirely).
  The `agent-reach` umbrella package is also not installed (its channel tree
  references the excluded platforms); the doctor pattern was reimplemented
  locally instead.

## 4. Allowlist (known-good repos)

Add entries only after a clean gate pass: `- owner/repo — gated clean YYYY-MM-DD`.

(empty — populate over time)

## 5. DEFER list + revisit triggers

| Tool | Why deferred | Revisit when |
|---|---|---|
| scorecard | needs GITHUB_TOKEN; reads GitHub, not local dirs | a repo-health gate (CI pinning, review coverage) becomes a requirement; token lives in ~/.config/gh |
| semgrep | heavy dep tree; overlaps gitleaks+trivy | regular multi-language SAST scanning of first-party code is needed |
| SkillEvaluator | Tier-3 needs LLM judges | scoring our own skills' quality matters more than threat-scanning them |

## 6. Non-negotiables recap

1. Quote every `"$(opensrc path …)"` substitution.
2. All quoted upstream versions were verified live 2026-08-27; re-run
   `check-versions.sh` rather than assuming.
3. English-only skills/scripts/output across all adopted capabilities.
4. No new cron jobs from this integration (watchdog cron cf9e330ae4c4 remains
   the only scheduled job); monthly tool upgrades are manual or follow-up work.
