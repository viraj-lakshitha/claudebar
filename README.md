# ClaudeBar

A macOS menu bar app for switching Claude Code between two accounts, such as personal and work, in one click. You no longer need `/logout` + `/login`.

```
✓ Personal — me@gmail.com   [Max]
    Work — me@company.com   [Pro]
─────────────
⚠︎ 1 claude session running
   Running sessions keep the old account until restarted
─────────────
Refresh                       ⌘R
Settings…                     ⌘,
Quit ClaudeBar                ⌘Q
```

- Switch accounts from the menu, or toggle with **⌃⌥⌘C** from anywhere.
- Each account shows its email, organization and plan.
- Warns you when `claude` sessions are running. They keep using the old account until you restart them.
- Can launch at login.
- Native SwiftUI for macOS 13+, with no dependencies.

## How it works

On macOS, Claude Code keeps its login in two places:

| Where | What |
| --- | --- |
| Keychain item `Claude Code-credentials` | OAuth tokens and plan |
| `~/.claude.json` → `oauthAccount` | Account identity: uuid, email, org |

ClaudeBar saves a snapshot of both for each account in its own Keychain items (`dev.claudebar.profile`). Switching writes the chosen account's snapshot back into those two places. Only the `oauthAccount` key of `~/.claude.json` is touched, and a backup is written next to it as `.claude.json.claudebar.bak`. Settings, history, projects and MCP servers stay shared between the accounts.

Claude Code rotates its refresh tokens. So ClaudeBar re-saves the tokens of the account you are leaving right before every switch, and every 15 seconds while an account is active. This keeps both snapshots valid.

ClaudeBar changes Claude Code's own Keychain item through `/usr/bin/security`, the same way Claude Code does, so macOS doesn't show Keychain prompts.

## Build

You need Xcode 15+ or the Swift 5.9+ command line tools, on macOS 13+.

```sh
swift test                 # unit tests
scripts/build-app.sh       # -> build/ClaudeBar.app
open build/ClaudeBar.app
```

Move `ClaudeBar.app` to `/Applications` before turning on **Launch at login**.

## Setup

1. Log in to your first account in Claude Code as usual.
2. Click the ClaudeBar icon and choose **Save Current Login…**, then give it a name such as "Personal".
3. In a terminal, run `claude`, then `/logout`, then `/login` with your second account.
4. Back in ClaudeBar, choose **Save Current Login…** again and name it, for example "Work".
5. Switch from the menu or with ⌃⌥⌘C. New `claude` sessions use the selected account.

Quit running `claude` sessions before you switch if you can. A session that is still running can refresh its old token and write it back after the switch.

## Layout

```
Sources/ClaudeBarCore   switching logic, Keychain/config access (unit tested)
Sources/ClaudeBar       SwiftUI menu bar app, hotkey, login item
Tests/                  XCTest suite with in-memory fakes
scripts/build-app.sh    SwiftPM build -> .app bundle
```
