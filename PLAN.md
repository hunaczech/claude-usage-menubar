# Claude Usage Menu Bar App (macOS)

## Context

The user wants a macOS menu bar app that shows what **percent of their Claude
subscription limit** they've burned (the same numbers Claude Code's `/usage`
shows: the 5-hour rolling window and the 7-day/weekly window).

**Verdict: not hard.** This is a small, well-trodden project — there are several
open-source native SwiftUI apps doing exactly this. Realistic effort: **a
focused day** for a working v1, a bit more for polish (launch-at-login, signing).

Two design choices were confirmed with the user:
- **Data source: the official `/usage` percentages** (authoritative, not an estimate).
- **Tech: a native SwiftUI app** (self-contained `.app`, no SwiftBar/xbar dependency).

### Key research finding (de-risks the project)

The official utilization % is **not** behind an undocumented "usage endpoint" —
it is returned as **HTTP response headers** on a normal request:

- `anthropic-ratelimit-unified-5h-utilization`  → current 5-hour window %
- `anthropic-ratelimit-unified-7d-utilization`  → weekly window %

Both **200 and 429** responses carry these headers. So the app sends one
**1-token request** (cheapest possible) to `https://api.anthropic.com/v1/messages`
with the OAuth token and reads the percentages off the response — no quota math,
no inferred limits, no reverse-engineered endpoint.

Auth uses the **same OAuth token Claude Code already stores** in the macOS
Keychain (service `Claude Code-credentials`), with the beta header
`anthropic-beta: oauth-2025-04-20` that makes that token valid against `/v1/messages`.
On first launch macOS prompts the user once to allow Keychain access (normal).

Confirmed locally during planning: `swift` is available; `node`+`ccusage` work
(fallback option); no SwiftBar/xbar installed (hence native app is the right call).

### Reference implementations to crib from (same approach, MIT-ish)
- `hamed-elfayome/Claude-Usage-Tracker` — native Swift/SwiftUI, usage limits.
- `AThevon/TokenEater` — reads OAuth token from Claude Code Keychain entry.
- `lionhylra/cc-usage-bar` — zero-auth variant (shells out to `claude`, scrapes `/usage`).
- `tddworks/ClaudeBar` — multi-tool quota menu bar app.

## Approach

A SwiftUI `MenuBarExtra` app that, on a timer, fetches the two utilization
percentages and renders them in the menu bar.

### 1. Project skeleton
- New Xcode macOS app (SwiftUI lifecycle), or a SwiftPM executable bundled as
  `.app`. Minimum target macOS 13 (MenuBarExtra requires 13+).
- App is **menu-bar-only**: set `LSUIElement = true` in `Info.plist` (no Dock icon).
- Single `@main App` using `MenuBarExtra("…", systemImage: …) { … }` with
  `.menuBarExtraStyle(.window)` for a small popover panel.

### 2. Credential access — `KeychainReader.swift`
- Read the OAuth credentials JSON from Keychain via `SecItemCopyMatching`
  (`kSecClassGenericPassword`, service `Claude Code-credentials`).
- Decode JSON → `{ accessToken, refreshToken, expiresAt }`.
- If `expiresAt` is past, run the OAuth refresh-token grant to mint a new access
  token (client id + token endpoint as used by Claude Code); cache it. If refresh
  fails, surface "Open Claude Code to re-auth" in the menu instead of crashing.

### 3. Usage fetch — `UsageClient.swift`
- POST to `https://api.anthropic.com/v1/messages` with:
  - `Authorization: Bearer <accessToken>`
  - `anthropic-beta: oauth-2025-04-20`
  - `anthropic-version: 2023-06-01`
  - Body: smallest valid request (Haiku model, `max_tokens: 1`, one-char prompt).
- Read `anthropic-ratelimit-unified-5h-utilization` and `…-7d-utilization` from
  `HTTPURLResponse.allHeaderFields` (works on both 200 and 429 — don't treat 429
  as fatal). Also capture any reset/`…-status` headers if present for the tooltip.
- Return a small `Usage` struct `{ fiveHourPct, weeklyPct, fetchedAt }`.

### 4. UI + polling — `AppModel.swift` (ObservableObject)
- `Timer` polls every ~5–10 min (each poll costs ~1 token — negligible; make the
  interval a setting). Also refresh on app focus / manual "Refresh" button.
- Menu bar **title** shows the headline number, e.g. `42%` (the higher / more
  binding of the two windows), optionally color-coded (green/amber/red thresholds).
- Dropdown panel shows both bars: "5-hour: 42%" and "Weekly: 18%", last-updated
  time, a Refresh button, and Quit.

### 5. Polish (optional v1.1)
- Launch at login via `SMAppService.mainApp.register()` (macOS 13+), toggle in menu.
- Threshold color/emoji in the title; notification when crossing e.g. 90%.
- Settings: poll interval, which window to headline.

### Fallback / alternative (document, don't build unless primary stalls)
If the header approach ever breaks, swap `UsageClient` to **shell out to the
`claude` CLI** and parse `/usage` output (the `cc-usage-bar` approach) — zero
Keychain/network code in the app. Keep `UsageClient` behind a protocol so the two
sources are interchangeable.

## Critical files (new project)
- `ClaudeUsageBarApp.swift` — `@main`, `MenuBarExtra`.
- `AppModel.swift` — state, timer, threshold logic.
- `KeychainReader.swift` — Keychain read + token refresh.
- `UsageClient.swift` — the 1-token request + header parsing (protocol + header impl).
- `Info.plist` — `LSUIElement = true`.

## Verification (end-to-end)
1. **Header sanity check first (before any Swift):** confirm the percentages are
   really in the headers using the user's own token, e.g.
   `curl -sD - -o /dev/null https://api.anthropic.com/v1/messages -H "authorization: Bearer <token>" -H "anthropic-beta: oauth-2025-04-20" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"."}]}' | grep -i ratelimit-unified`
   → expect `…-5h-utilization` and `…-7d-utilization` lines. (Requires the user
   to provide/approve token access — was correctly auto-denied during planning.)
2. Cross-check the returned percentages against what `claude` shows in `/usage`.
3. Build & run the app: number appears in the menu bar; dropdown shows both windows.
4. Force a stale token (or wait past expiry) → confirm refresh path works.
5. Toggle launch-at-login, reboot, confirm it reappears.

## Risks / notes
- **Undocumented headers** — Anthropic could rename/remove them; keep the CLI
  fallback ready and isolate the parsing in one file.
- **Each poll spends ~1 token** of quota; keep the interval modest.
- **Token handling is sensitive** — read-only from Keychain, never log/transmit
  the token anywhere except `api.anthropic.com`.
- This relies on the user being on a **Pro/Max subscription** authed through
  Claude Code (OAuth), not an `ANTHROPIC_API_KEY` setup.
