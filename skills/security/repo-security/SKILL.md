---
name: repo-security
description: "Security-gate any repo before clone/install/run on this Mac: leaked-secret scan (gitleaks), dependency CVE scan (osv-scanner), agent-skill/MCP threat scan (NVIDIA SkillSpector), package source fetch (opensrc). Use WHEN about to git clone an unknown repo, npm/uv install unfamiliar packages, or adopt a third-party agent skill/MCP server."
version: 0.1.0
author: mac-toolbox v2 (TysAIs)
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [security, supply-chain, vetting, repos]
prerequisites:
  commands: [gitleaks, osv-scanner, opensrc, skillspector]
---

# Repo Security Gate

Every unknown repo gets gated BEFORE its code runs here. L0-native CLIs only —
never needs GUI/browser layers.

## The gate

```bash
# Pre-clone / pre-install (shallow-clones the URL into a throwaway dir):
scripts/repo-intake/gate-clone.sh https://github.com/someone/repo [--strict]

# Post-install, pre-run (already-on-disk project):
scripts/repo-intake/gate-run.sh <project-dir>

# All-in-one normalized report -> JSON + verdict:
scripts/repo-intake/gate-report.sh <dir> --json-out /tmp/gate.json

# Version drift check (warns, never downgrades):
scripts/repo-intake/check-versions.sh
```

Exit semantics: `0` clean · `1` findings (WARN; FAIL under `--strict`) ·
`2` tool missing → FIX ENVIRONMENT first, never skip the gate.

Scanners run independently: gitleaks (secrets in history/worktree),
osv-scanner (known CVEs in lockfiles vs OSV.dev). If the repo contains
SKILL.md / mcp.json it is skill-shaped → skillspector also scans for prompt
injection, tool poisoning, exfiltration. trivy fs adds HIGH/CRITICAL dep/IaC
coverage when installed.

Reading reports: gitleaks writes JSON to `/tmp/gate-gitleaks-*.json`
(fields: RuleID, File, Secret); osv-scanner JSON groups vulns per package;
skillspector emits SARIF + 0–100 risk score. WARN ≠ safe: read the finding,
decide, and only then proceed with install/run.

## Package source reading (opensrc)

Fetch real, version-matched source of any npm/PyPI/crates/GitHub package:

```bash
cat "$(opensrc path zod)/src/index.ts"          # ALWAYS quote the substitution
opensrc path pypi:requests                      # non-npm registries
opensrc path vercel/next.js                     # whole repos
find "$(opensrc path pypi:flask@3.0.0)" -name "*.py"
```

Cache lives at `~/.opensrc/` (env override `OPENSRC_HOME`). Never commit cache
contents anywhere. First fetch of big repos is slow — batch pre-fetch.

## Tool inventory

| Tool | Install | Role |
|---|---|---|
| opensrc 0.7.x | `npm install -g opensrc` | fetch/read package+repo source |
| gitleaks 8.30.x | `brew install gitleaks` | secret detection |
| osv-scanner 2.5.x | `brew install osv-scanner` | dependency CVEs |
| trivy 0.74+ (optional) | `brew install trivy` | deeper fs/IaC scan (phase 2) |
| skillspector 2.x | `uv tool install git+https://github.com/NVIDIA/skillspector.git` | agent-skill/MCP threats |

Install rules: skillspector is **git+uv only** (NOT on PyPI/npm — do not copy a
PyPI line from anywhere). Gate defaults are keyless (`--no-llm`,
static-only); LLM mode is opt-in via `SKILLSPECTOR_PROVIDER`. Never bake
scanner caches or `~/.opensrc/` contents into any repo.

## Policy

See `docs/tooling-policy.md` for the machine-level rule: every agent on this
Mac gates before installing or running unknown code, and the DEFER list
(scorecard, semgrep) with revisit triggers.
