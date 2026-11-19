# Claude Usage menu bar

Shows your Claude plan limits (5-hour session, weekly) in the macOS menu bar, e.g. `5h 12%  7d 35%`. Turns orange at 75%, red at 90%. Click for reset times and per-model weekly limits, or to switch to horizontal or vertical bars.

## How it works

Reads the OAuth token Claude Code keeps in the `Claude Code-credentials` Keychain item and polls `https://api.anthropic.com/api/oauth/usage` (the same data as `/usage` in Claude Code) every 5 minutes. It never refreshes the token itself; if it expires, opening Claude Code refreshes it.

## Build and run

How:

```sh
./build.sh
```

This compiles, installs to `/Applications/ClaudeUsage.app`, and relaunches it, so the same command works for every change. To start it at login, check **Launch at Login** in its menu.

No dependencies beyond the Xcode command-line tools (`swiftc`).
