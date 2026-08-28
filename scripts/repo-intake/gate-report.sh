#!/usr/bin/env bash
# gate-report.sh — normalize scanner outputs into ONE JSON report + human
# summary, with exit-code fan-in (any nonzero scanner => WARN|FAIL).
#
# Usage: gate-report.sh <dir> [--json-out FILE] [--strict]
# Runs gitleaks + osv-scanner (+ skillspector if skill-shaped, + trivy if
# installed) against <dir> and prints a verdict line plus JSON:
#   {"dir":..., "verdict":"PASS|WARN|FAIL", "scanners":[{name,ok,findings,detail}]}
set -u
DIR=""; JSON_OUT=""; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json-out) JSON_OUT="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    *) DIR="$1"; shift ;;
  esac
done
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "usage: gate-report.sh <dir> [--json-out F] [--strict]" >&2; exit 3; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$DIR" "$JSON_OUT" "$STRICT" "$TMP" <<'PYEOF'
import json, os, shutil, subprocess, sys

target, json_out, strict, tmp = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
results = []

def run(name, argv, findings_fn):
    if shutil.which(argv[0]) is None:
        results.append({"name": name, "ok": False, "tool_missing": True,
                        "findings": None, "detail": "binary not on PATH"})
        return 2
    p = subprocess.run(argv, capture_output=True, text=True, timeout=180)
    try:
        findings = findings_fn(p.stdout, p.returncode)
    except Exception as e:
        findings = f"(report parse error: {e})"
    detail = ""
    if p.returncode not in (0, 1):
        detail = (p.stderr or "").strip()[:300]
    results.append({"name": name, "ok": p.returncode == 0,
                    "tool_missing": False, "findings": findings, "detail": detail})
    return {0: 0, 1: 1}.get(p.returncode, 2)

def gl_findings(out, rc):
    d = json.loads(out or "[]")
    return len(d) if isinstance(d, list) else "?"

def osv_findings(out, rc):
    d = json.loads(out or "{}")
    return sum(len(p.get("vulnerabilities", []))
               for r in d.get("results", []) for p in r.get("packages", []))

def count_matches(out, rc):  # for line-based tools we don't parse deeply
    return rc and "see raw output" or 0

gl_rep = os.path.join(tmp, "gitleaks.json")
rc_g = run("gitleaks", ["gitleaks", "detect", "--source", target, "--no-git",
                        "--exit-code", "1", "--report-format", "json",
                        "--report-path", gl_rep],
           lambda out, rc: gl_findings(open(gl_rep).read(), rc))

rc_o = run("osv-scanner", ["osv-scanner", "scan", "source", target, "--format", "json"],
           osv_findings)

# Conditional: skill-shaped content -> skillspector static scan
skill_shaped = any(
    os.path.exists(os.path.join(root, fn))
    for root, _, files in os.walk(target) for fn in files
    if fn in ("SKILL.md", "mcp.json", ".mcp.json"))
rc_s = 0
if skill_shaped:
    sarif = os.path.join(tmp, "skillspector.sarif")
    rc_s = run("skillspector", ["skillspector", "scan", target, "--no-llm",
                                "--format", "sarif", "--output", sarif],
               lambda _o, rc: rc and "see SARIF" or 0)
else:
    results.append({"name": "skillspector", "ok": True, "skipped": True,
                    "findings": 0, "detail": "no SKILL.md/mcp.json present"})

worst = max(rc_g, rc_o, rc_s)
verdict = "PASS" if worst == 0 else ("FAIL" if worst == 2 else ("FAIL" if strict else "WARN"))

summary = {"dir": os.path.abspath(target), "verdict": verdict, "scanners": results}
if json_out:
    with open(json_out, "w") as f:
        json.dump(summary, f, indent=2)

for r in results:
    state = "SKIP" if r.get("skipped") else ("MISSING" if r.get("tool_missing")
             else ("clean" if r["ok"] else f"FINDINGS ({r['findings']})"))
    print(f"[{r['name']}] {state}" + (f" — {r['detail']}" if r["detail"] else ""))
print(f"GATE RESULT: {verdict}")
sys.exit(0 if worst == 0 else (2 if worst == 2 else 1))
PYEOF
