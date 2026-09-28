# ClaudeBar

A macOS menu bar app for switching Claude Code between two accounts, such as personal and work, in one click. You no longer need `/logout` + `/login`.

Menu bar:  👤 Personal · 23%

```
┌ Claude Code Accounts ───────────────── ⟳ ┐
│ (P) Personal          Max   ✓ Active     │
│     me@gmail.com                         │
│     Session (5h)                   23%   │
│     ████░░░░░░░░░░░░  Resets in 2h 10m   │
│     Weekly                         41%   │
│     ███████░░░░░░░░░  Resets Thu 3:00 PM │
│ (W) Work              Pro   [Switch]     │
│     Session (5h)  …                      │
│──────────────────────────────────────────│
│ ⊕ Add Account                      ⚙  ⏻ │
└──────────────────────────────────────────┘
```

- The menu bar shows the **current account** and how much of its **5-hour session limit** is used.
- The panel shows every saved account's **usage limits**: session (5h), weekly, and per-model weekly where your plan has them. It also shows when each one resets.
- **Add Account** walks you through adding a new login, so you don't need to touch config files.
- Switch with one click, or toggle with **⌃⌥⌘C** from anywhere. With more than two accounts, the shortcut goes through them in turn.
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

Usage limits come from the same endpoint Claude Code's `/usage` command uses (`api.anthropic.com/api/oauth/usage`). ClaudeBar calls it with each account's saved access token every 5 minutes. When an inactive account's token has expired, ClaudeBar shows the last numbers it fetched. They update again after you switch to that account.

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

1. Log in to Claude Code as usual.
2. Click the ClaudeBar icon, then **Add Account**. ClaudeBar first saves the account you're logged in to, and asks for a name such as "Personal".
3. ClaudeBar then opens Terminal and runs `claude`. Type `/login` and sign in with your other account.
4. ClaudeBar notices the new login and asks you to name it, for example "Work". That's it.
5. Switch from the panel or with ⌃⌥⌘C. New `claude` sessions use the selected account.

Quit running `claude` sessions before you switch if you can. A session that is still running can refresh its old token and write it back after the switch.

## Layout

```
Sources/ClaudeBarCore   switching logic, Keychain/config access (unit tested)
Sources/ClaudeBar       SwiftUI menu bar app, hotkey, login item
Tests/                  XCTest suite with in-memory fakes
scripts/build-app.sh    SwiftPM build -> .app bundle
```
