# Claude Usage menu bar

Shows your Claude plan limits (5-hour session, weekly) in the macOS menu bar, e.g. `5h 12%  7d 35%`. Turns orange at 75%, red at 90%. Click for reset times and per-model weekly limits.

## How it works

Reads the OAuth token Claude Code keeps in the `Claude Code-credentials` Keychain item and polls `https://api.anthropic.com/api/oauth/usage` (the same data as `/usage` in Claude Code) every 5 minutes. It never refreshes the token itself; if it expires, opening Claude Code refreshes it.

## Build and run

How:

```sh
./build.sh
open build/ClaudeUsage.app
```

To start it at login, copy `build/ClaudeUsage.app` to `/Applications` and add it under **System Settings → General → Login Items**.

No dependencies beyond the Xcode command-line tools (`swiftc`).
