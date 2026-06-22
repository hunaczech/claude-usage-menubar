# Claude Usage Menu Bar (macOS)

A tiny native SwiftUI menu-bar app that shows what percent of your Claude
subscription limit you've used — the same `5-hour` and `7-day` numbers Claude
Code's `/usage` reports.

It reads those percentages straight off the **HTTP response headers** of a
minimal 1-token request to `api.anthropic.com`, authed with the OAuth token
Claude Code already keeps in your macOS Keychain. No quota math, no scraping.

## Requirements

- macOS 13+ (the menu-bar UI uses `MenuBarExtra`).
- Swift toolchain (Xcode or Command Line Tools) to build.
- A Claude **Pro/Max** subscription signed in through **Claude Code** (OAuth),
  not an `ANTHROPIC_API_KEY` setup.

## Build & run

```bash
./scripts/bundle.sh          # compiles + wraps into dist/ClaudeUsageBar.app
open dist/ClaudeUsageBar.app  # launch (appears only in the menu bar)
```

On first launch macOS asks once for permission to read the Keychain item — allow it.

To install, drag `dist/ClaudeUsageBar.app` into `/Applications`.

## Using it

- The menu bar shows the higher of the two windows, e.g. `42%`
  (green < 70%, amber 70–89%, red ≥ 90%).
- Click it for a panel with both windows, last-updated time, and a **Refresh** button.
- Toggles for **Launch at login**, **Notify at 90%**, and a refresh-interval picker.

## Verify the data source (optional, recommended once)

Confirm the percentages really come back in the headers, using your own token:

```bash
curl -sD - -o /dev/null https://api.anthropic.com/v1/messages \
  -H "authorization: Bearer <token>" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"."}]}' \
  | grep -i ratelimit-unified
```

Expect `…-5h-utilization` and `…-7d-utilization` lines. Cross-check against
`claude`'s `/usage` output.

## How it's built

| File | Role |
|------|------|
| `Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` | `@main`, `MenuBarExtra`, dropdown view |
| `Sources/ClaudeUsageBar/AppModel.swift` | state, polling timer, thresholds, notifications |
| `Sources/ClaudeUsageBar/KeychainReader.swift` | Keychain read + OAuth token refresh |
| `Sources/ClaudeUsageBar/UsageClient.swift` | the 1-token request + header parsing |
| `Sources/ClaudeUsageBar/LaunchAtLogin.swift` | `SMAppService` wrapper |
| `Resources/Info.plist` | `LSUIElement = true` (menu-bar-only, no Dock icon) |
| `scripts/bundle.sh` | build + wrap into `.app` + ad-hoc sign |

## Notes & caveats

- The utilization headers are **undocumented** — Anthropic could rename/remove
  them. Parsing is isolated in `UsageClient` behind the `UsageProviding`
  protocol so a CLI-based fallback can replace it without touching the rest.
- Each poll spends ~1 token of quota; the default interval is 5 min (configurable).
- The token is read-only from the Keychain, refreshed only in memory, and never
  logged or sent anywhere except `api.anthropic.com` / `console.anthropic.com`.
