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
  - `ContentView.swift`: the notch root view, with open/closed layout and compact-mode branching.
  - `components/Notch/`: `CompactHomeView`, `NotchHomeView`, the SkyLight window, live-activity stack and power notice.
  - `components/LiveActivities/`, `components/OSD/`: the temporary alerts and HUD replacement.
  - `components/Calendar/`, `Webcam/`, `Shelf/`, `Music/`, `Tabs/`: features.
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
- Test on both a notched display and a non-notched one, since the app must work on a MacBook Air, Mac mini and external monitors. When testing on this machine, don't take over the user's screen. See the global instructions on GUI testing.
- Build with Xcode (`boringNotch.xcodeproj`, scheme `boringNotch`). Deployment target is macOS 14.0, but check the target before using newer APIs.
- Mark anything that depends on Apple private API (SkyLight, MediaRemote) clearly. It is the likeliest thing to break on a new macOS release.

## Licensing

Everything here is GPL-3.0. Code copied from other projects (MewNotch and DynamicNotch are GPL-3.0 reference implementations) needs its attribution kept and has to be compatible with GPL-3.0. Add new third-party notices to `THIRD_PARTY_LICENSES/`.
