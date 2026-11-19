# Claude Usage menu bar

Shows your Claude plan limits (5-hour session, weekly) in the macOS menu bar, e.g. `5h 12%  7d 35%`. Turns orange at 75%, red at 90%. Click for reset times and per-model weekly limits, or to switch to horizontal or vertical bars.

| Choice | Display |
| --- | --- |
| Vertical Bars | <kbd><img width="69" height="28" alt="Screenshot 2026-11-19 at 2 13 30 PM" src="https://github.com/user-attachments/assets/2ab40575-d260-4c31-9b7e-53d498dfbe8e" /></kbd> |
| Horizontal Bars | <kbd><img width="131" height="27" alt="Screenshot 2026-11-19 at 2 15 02 PM" src="https://github.com/user-attachments/assets/48f53e7d-4b0a-498b-8b47-3fcdacfd2851" /></kbd> |
| Horizontal w/percent | <kbd><img width="129" height="29" alt="Screenshot 2026-11-19 at 2 17 22 PM" src="https://github.com/user-attachments/assets/e6671681-86a2-4c05-9397-c62489cf5a3d" /></kbd> |
| Percentage | <kbd><img width="112" height="26" alt="Screenshot 2026-11-19 at 2 15 35 PM" src="https://github.com/user-attachments/assets/1f30fd1b-108a-4bd1-a478-ca1cd61d1543" /></kbd> |


## How it works

Reads the OAuth token Claude Code keeps in the `Claude Code-credentials` Keychain item and polls `https://api.anthropic.com/api/oauth/usage` (the same data as `/usage` in Claude Code) every 5 minutes. It never refreshes the token itself; if it expires, opening Claude Code refreshes it.

## Build and run

How:

```sh
./build.sh
```

This compiles, installs to `/Applications/ClaudeUsage.app`, and relaunches it, so the same command works for every change. To start it at login, check **Launch at Login** in its menu.

No dependencies beyond the Xcode command-line tools (`swiftc`).
