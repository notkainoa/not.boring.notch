# Vision

A compact, always-on notch that hosts a small set of built-in features and brings Raycast and its extensions into the notch. Built on Boring Notch. Stays easy to rebase on upstream.

Reference apps: **Vorsaint** (animation and "expand for big things" feel), **MewNotch** (lock screen, multi-display, HUDs), **DynamicNotch** (temporary alerts such as Bluetooth and Wi-Fi). MewNotch and DynamicNotch are GPL-3.0 references, so check licenses before copying any code.

## Principles

1. **Compact only.** There is one notch mode.
2. **Expand for big things.** Calendar, camera and similar features grow the notch horizontally and vertically on demand, then collapse.
3. **Works on every Mac.** Notched MacBooks, MacBook Air and other non-notched Macs, and external displays.
4. **Independent of upstream.** We snapshotted Boring Notch and diverge freely. See `docs/UPSTREAM-SYNC.md`.

## Work items

### 0. Quick win: Quit in the notch context menu
Right-clicking the notch (`.contextMenu` in `ContentView.swift`) only offers Settings. Add **Quit** (⌘Q) that calls `NSApp.terminate(nil)`.

### 1. Compact mode only
Today `Defaults[.compactMode]` (default `false`) switches `ContentView` between the full tabbed notch and `CompactHomeView`, which only shows music.
- Remove the non-compact layout and the tab bar. Delete the setting and migrate existing users.
- Make compact the only layout. Lay out `CompactHomeView` as the home view.
- Make everything else reachable from compact (items 2 and 3).
- Delete the old tabbed UI and the code for it. We don't merge upstream, so there is no reason to keep it.
- Keep what the old tabs used: the calendar, mirror (webcam), shelf and music views are reused inside expandable panels.

### 2. Expandable panels
A compact bar with buttons (or activity chips) for each feature. Clicking one expands the notch **both horizontally and vertically** to the size that feature needs, and collapsing returns to compact.
- **Calendar:** expanded size fits the date strip and event list.
- **Mirror (camera):** expanded size matches the camera aspect ratio.
- Others later: shelf, Raycast panels.
- Each panel declares its own preferred size. Size changes are animated morphs of the notch shape, with no cross-fade between two separate windows. Tune the spring and timing against Vorsaint.
- Needs per-panel geometry in the notch view model, and hover/hit-testing that follows the changing frame (note the existing comment in `ContentView` about compact hit-testing).
- Upstream's extension platform has "compact workspace" prep. We're not using that platform (see sync doc), but we can glance at it for geometry ideas.

### 3. Lock screen customization
Today `showOnLockScreen` (default off) shows the entire notch on the lock screen through SkyLight windows, so everything is available while locked.
- Add a separate list of features available while locked. Each feature toggles independently, for example now-playing and battery on, calendar details, shelf and mirror off.
- Respect privacy: calendar event titles and shelf contents should be hideable or redacted when locked.
- Settings UI: a "Lock screen" section with per-feature switches.
- Compare MewNotch's lock-screen settings before designing. We're **not** adopting upstream's lock-screen widget containers (#1498).
- Mine upstream PR #1346 (unlock animation with privacy lockdown). It shows a padlock that morphs open on unlock and hides private content and interaction while locked. Take its SkyLight window-swap fix and the idea of a locked state. Its list of what's private is hardcoded, and ours is user-configurable.
- Known bug to test for in the existing `showOnLockScreen`: after unlock the SkyLight window's transparent margins can swallow desktop clicks near the notch. #1346 fixes it by replacing the window with a fresh one.
- **Deferred.** The full lock-screen settings tab comes after the Raycast integration, because most of what the user would configure (Raycast panels and activities) doesn't exist yet. Until then lock-screen behavior stays as it is today, apart from the click-swallow check.
- Lock screen support is undocumented upstream. Add notes to the README as we go.

### 4. Bluetooth live activity
Show a temporary alert when a Bluetooth device connects or disconnects, with its battery level where available.
- Adopt upstream PR #1668 "Show Bluetooth accessory connections with battery level" (connect/disconnect banner, AirPods left/right levels, HID fallback for Apple keyboards and mice, opt-in because of the Bluetooth permission and entitlement). Cherry-pick and adapt it.
- Before finalizing, read how DynamicNotch and MewNotch do Bluetooth alerts and compare. Both are GPL-3.0, so code can be reused with attribution.
- Related: the same alert mechanism should cover Wi-Fi and other connectivity events later. Battery and charging alerts already exist.

### 5. Non-notch devices
Upstream already handles displays without a notch (`hasNotch`, `nonNotchHeight`, height migration, and a compact notch on external displays). Today the idle non-notch notch is an empty pill. Adopt upstream PR #1718, which adds an optional clock in the closed notch on those displays.
- Test devices: the user's older, non-notched MacBook Air (M1-era or earlier) is the main test device. Also test an external monitor. Newer Airs have a notch.
- Known to need checking: floating position, corner shape, hover target, fullscreen behavior.
- Make sure the new expandable panels (item 2) size correctly without a notch.

### 6. Raycast bridge
Let Raycast and its extensions drive the notch. Design to settle:
- Transport: URL scheme, local socket or HTTP, or Raycast Script Commands calling a CLI that talks to the app.
- What Raycast can send: temporary alerts, live activities, progress, and content panels (item 2).
- This is **not** an extension store or runtime. It integrates the Raycast extensions the user already has installed and lets them drive things from the notch. That is why we're not using upstream's extension platform.
- Needs research on what Raycast allows from outside Raycast (deeplinks, URL schemes, Script Commands, any local API, reading installed extensions) before committing to a design.

### 7. Built-in: per-app volume
Per-app volume mixer in the notch. Needs a research spike on Core Audio process taps (macOS 14.2+) versus a virtual audio driver. Keep it isolated from upstream files.

### 8. Built-in: now playing
Already provided by Boring Notch. Keep it, and keep its compact layout.

### 9. Release workflow (not started)
We deleted upstream's release pipeline in the cleanup commit because it depended on upstream's signing secrets, GitHub App and update feed. When we're ready to ship, we need our own:
- **Signing and notarization:** Developer ID certificate, notarytool credentials, stored as repo secrets (none exist yet). Decide whose Apple Developer account owns the certificate. The only code-signing identity on the dev Mac is another person's Developer ID cert, so don't use that one.
- **Build and release automation:** a workflow that builds a release configuration, signs and notarizes, creates the DMG with `Configuration/dmg/`, and publishes a GitHub release. Upstream's deleted `release.yml`, `nightly.yml` and `build_reusable.yml` are good references; find them with `git log --diff-filter=D --name-only` or in upstream's repo.
- **Auto-update (Sparkle):** auto-update is **disabled** right now. The feed URL and upstream's public key were removed from `Info.plist`, `feedURLString` returns `nil` and the updater is never started. To re-enable: generate our own Sparkle EdDSA key pair, host an appcast (GitHub Pages or release assets), set `SUFeedURL` and `SUPublicEDKey`, and restore `updaterController.startUpdater()` in `boringNotchApp.swift`. Never point it back at upstream's feed, because it would replace our app with Boring Notch.
- **Stable dev signing:** separate from release. A stable local signing identity keeps macOS permissions between dev rebuilds (see AGENTS.md "Building and testing").
- **Bundle ID:** the app still uses upstream's `theboringteam.boringnotch` bundle ID and XPC service name. Choose our own before the first release, update `XPCHelperClient.swift`, and plan the migration from the installed Boring Notch.
- **Nightly or beta channel:** optional later.

## Order of work

1. Build the snapshot and run it on the notch-less MacBook Air and an external monitor. Record what works.
2. Quit in the context menu (item 0).
3. Compact-only (item 1) together with the expandable panel mechanism (item 2) and the calendar and mirror panels.
4. Adopt the non-notch clock (#1718) and the Bluetooth banner (#1668), after comparing with DynamicNotch and MewNotch (items 4 and 5).
5. Check the lock-screen click-swallow bug and add the locked-state skeleton (item 3, first pass only).
6. Raycast research spike, then the bridge (item 6).
7. Lock-screen settings tab (item 3, full), once Raycast content exists.
8. Per-app volume (item 7).
9. Release workflow (item 9), before the first public build.

## Not goals

- A closed-source or paid release. The project is GPL-3.0.
- Feature parity with every Boring Notch option. Removing settings we don't need is fine.
