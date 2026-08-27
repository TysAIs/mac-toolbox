# Computer Control Policy — Single Source of Truth

Version: 2026-08-27.1
Owner: you. Edit ONLY this file, then run `scripts/stamp-computer-control.sh` to propagate the compact ladder into every agent's SOUL.md. Never hand-edit the stamped blocks inside SOUL.md files.

---

## Hardware baseline (this machine)

<!-- Filled automatically by scripts/detect-hardware.sh during install -->
{{HARDWARE_BASELINE}}

- **Role**: this Mac runs the agent fleet + desktop automation. Configure where heavy model inference lives (local server, cloud API) in your agent platform — not here.

## Routing ladder — strict priority order

1. **Targeted CLI/skill exists** → use it. Cheapest and most reliable.
2. **Known exact AppleScript/JXA** → `osascript`, or `mac.script()` inside the harness.
3. **Native-app GUI work** → **macos-harness** (skill `apple/macos-harness`): background-window screenshots, PID-targeted clicks/keys, Accessibility tree. No focus-stealing, no cursor movement.
   - System Settings / consent-sheet quirks: keep a recipes skill for the gnarly panes.
4. **Web tasks** → your configured browser-automation workflow, in this order:
   - **browser-use** (`browser_exec` tool / `browser-use` CLI): headless or CDP-attached automation of real browser sessions, ideal for page automation, extraction, form-filling.
   - **cua-driver** (`computer_use` tool / `cua-driver` CLI): full desktop + browser control for GUI-level tasks that need pixel/coordinate input (consent dialogs, canvas apps, native UI).
   - Prefer **Brave CDP** (`~/bin/brave-cdp.sh`, port 9222) when the task needs the user's live logged-in Brave session.
   - Do NOT install or use third-party closed-source browsers (ego-lite / citrolabs) — the stack above is native to Hermes and open source.
5. **Fallback only**: full-screen computer-use / vision drivers.

## Resource hygiene — browser tabs & processes (mandatory)

Bots that leave artifacts behind degrade the whole Mac for everyone. Rules:

- **Close every CDP/browser tab you open, when the task ends.** Count what you
  opened; close the same set (`GET http://localhost:9222/json/close/<tabId>`,
  or `browser` helpers). Keep **≤ 2 tabs per host** alive across the session.
- **Dedupe before opening**: check `GET /json/list` first — if a tab for that
  URL/host already exists, reuse it instead of spawning another.
- **Kill your own zombie workers**: a `hermes chat -q` / subprocess worker that
  is still alive after its card completes (or shows 0% CPU for hours) gets
  terminated by whoever notices it — do not "leave it running just in case".
- **Verify before finishing a browser task**: `curl -s localhost:9222/json/list`
  and confirm tab count is back near your starting baseline. A finished task
  that leaves +10 tabs is an incomplete task.
- The fleet watchdog surfaces violations as kanban cards to the owning bot.

## Web automation safety rules

- Prefer official APIs over UI automation when they exist.
- Use dedicated automation accounts on platforms whose ToS restrict automation; keep personal identity out of automated flows.
- Rate-limit to human speeds; never automate engagement-farming or bulk actions.
- Human approval gate before: posting/publishing, purchasing, deleting, or any irreversible web action.
- When unsure about a site's rules, ask before automating.

## Safety invariants

- Input targets already-running app processes only.
- Never move the physical cursor; never force an app to the foreground.
- After ONE failed verified burst, switch approach. Never repeat-click, bulk-type, or loop blind input.
- Permission errors → tell the user exactly which System Settings toggle to grant; do not retry.
