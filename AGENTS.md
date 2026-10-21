# AGENTS.md

not.boring.notch is a fork of [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0). It is a macOS notch app (SwiftUI + AppKit) that is compact-only and bridges to Raycast. Read `VISION.md` for what we're building and `docs/UPSTREAM-SYNC.md` for how we stay in sync with upstream.

## Git

- Remotes: `origin` = notkainoa/not.boring.notch, `upstream` = TheBoredTeam/boring.notch.
- Our `main` is the product branch. It started as a one-time snapshot of upstream `dev` (v2.8-rc.2 plus fixes, merged with upstream `main`'s trailing CI commits). Upstream's own `main` is stale, so it is not the base for anything.
- **We have deliberately diverged from upstream and do not merge it.** `upstream` stays as a fetch-only remote so we can cherry-pick security and macOS-compatibility fixes and look at their PRs. See `docs/UPSTREAM-SYNC.md`.
- Commits are authored as Kainoa Newton <k@kainoa.me>. Flag it if `git config user.email` differs.
- Don't push or open PRs unless asked. `origin/main` is still upstream's stale `main`, and our `main` is a fast-forward of it.
- Never rewrite history that has been pushed.

## Project layout

- `boringNotch/` is the app. Key places:
  - `ContentView.swift`: the notch root view, with the closed layout, the open header and panel host, and hover/close handling.
  - `components/Notch/`: `NotchPanel` (the panel registry and geometry, see `docs/PANELS.md`), `NotchPanelHeader`, `CompactHomeView` (the home panel), the SkyLight window, live-activity stack and power notice.
  - `components/LiveActivities/`, `components/OSD/`: the temporary alerts and HUD replacement.
  - `components/Calendar/`, `Webcam/`, `Shelf/`, `Music/`: features, shown as panels.
  - `managers/NotchWindowManager.swift`: per-display windows and lock-screen (SkyLight) toggling.
  - `models/Constants.swift`: every `Defaults` key. Add settings here.
  - `sizing/matters.swift`: notch size computation. It has non-notch handling.
- `BoringNotchXPCHelper/`: XPC helper for sandbox-restricted work such as media keys and HUD interception.
- `mediaremote-adapter/`: now-playing source on macOS 15.4+.
- Settings UI lives in `components/Settings/Views/`.

## Working agreements

- We're not tracking upstream, so refactor and delete freely. Remove code for features we cut (non-compact layout, tabs) instead of leaving it dormant.
- New user-facing strings go in `Localizable.xcstrings`.
- Upstream's Crowdin/localization pipeline is theirs. Don't depend on it. Check `crowdin.yml` and the workflows before relying on or pushing CI, and disable workflows that target upstream infrastructure (release signing, appcast, updater) if they would run in our fork.
- New settings are `Defaults` keys in `Constants.swift` with a settings-UI entry.
- Keep the notch cheap at rest (CPU, memory, no polling). Upstream has fixed several hot-path regressions.
- The app must work on notched and non-notched displays (MacBook Air, Mac mini, external monitors). Design for both. See "Building and testing" for how testing works.
- Deployment target is macOS 14.0, but check the target before using newer APIs.
- Mark anything that depends on Apple private API (SkyLight, MediaRemote) clearly. It is the likeliest thing to break on a new macOS release.

## Building and testing

Use `scripts/dev.sh` from any checkout or worktree. If your worktree predates it, get it with `git cherry-pick 41926b5` (or `git merge main`).

```sh
scripts/dev.sh          # build and run this checkout
scripts/dev.sh build    # build only
scripts/dev.sh kill     # stop this checkout's copy
```

- It builds ad-hoc signed into `.build/dev` in your own checkout, which is gitignored, so worktrees don't share build output.
- `run` starts the binary directly (logs go to the terminal, Ctrl-C quits).
- The dev build has the **same bundle ID and XPC service name as the installed Boring Notch**. `run` refuses to start while `/Applications/Boring Notch.app` is running, so the user has to quit it first (the notch context menu has Quit). Only one build can run at a time.
- Ad-hoc signing changes identity on each rebuild, so macOS re-asks for Accessibility and other permissions after a rebuild. Expect that and tell the user when a feature depends on one.
- The XPC service name in `XPCHelperClient.swift` is hard-coded to the helper's bundle ID. Don't change bundle IDs without updating it.

### Agent rules for testing

- **Agents never launch the app.** Several agents share this Mac and the user may be using it. Don't run `scripts/dev.sh run`, `open` the built app, or drive the desktop. Verify with `scripts/dev.sh build` (or the `xcodebuild` command in that script), unit tests, and code reasoning only.
- `scripts/dev.sh build` is the compile check. Report its result honestly, including environment failures.
- Be explicit about what is unverified at runtime. Lock screen, Bluetooth hardware, HUD interception, notch animation feel and non-notch displays can't be confirmed by building.

### When you finish, hand the user a test plan

End your final report with a **"How to test"** section the user can follow, containing:
1. The exact commands, with the absolute worktree path, for example `cd ~/.t3/worktrees/not.boring.notch/<worktree> && scripts/dev.sh`.
2. A reminder to quit the installed Boring Notch first if it's running.
3. Which permissions the feature needs (Accessibility, Bluetooth, Calendar, Camera, and so on), and that they may need re-granting after a rebuild.
4. A short checklist of what to try and what a correct result looks like, including edge cases (non-notch display, external monitor, lock screen, no music playing, etc., as relevant).
5. Known gaps: what you couldn't verify and where you'd expect problems.

The user's test devices are a non-notch MacBook Air M1 and, later, an external monitor.

## Licensing

Everything here is GPL-3.0. Code copied from other projects (MewNotch and DynamicNotch are GPL-3.0 reference implementations) needs its attribution kept and has to be compatible with GPL-3.0. Add new third-party notices to `THIRD_PARTY_LICENSES/`.
