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
A compact bar with buttons (or activity chips) for each feature, below now playing on the home view. Build it as one generic bar with an item type (built-in panel, Raycast command, later others) so Raycast pins (item 6) drop in without redoing the layout. Clicking one expands the notch **both horizontally and vertically** to the size that feature needs, and collapsing returns to compact.
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
Let Raycast and its extensions drive the notch. This is **not** an extension store or runtime. It integrates the Raycast extensions the user already has installed and lets them drive things from the notch. That is why we're not using upstream's extension platform. Research and design are in `docs/raycast-integration.md`.
- **Pinned commands in the home bar.**
  - The user pins installed Raycast commands into the item 2 bar, after the built-in panel buttons, with an overflow "⋯" that opens a Raycast panel.
  - Clicking runs the command by `raycast://` deeplink:
    - `no-view` commands run in the background with a brief "sent" state.
    - Commands with arguments expand into a small form.
    - `view` commands collapse the notch and open Raycast.
  - Commands are discovered from `~/.config/raycast/extensions/*/package.json`.
- **Settings → Raycast:** search installed commands, pin and reorder them, and a "Try it" button so Raycast's one-time confirmation happens while pinning.
- **Local API:** a unix socket plus a `notchctl` CLI (and a URL scheme for one-liners) that accepts alerts, live activities with progress, and panel content. It also serves non-Raycast clients.
- **Companion Raycast extension:** `no-view` commands that push alerts, progress and panels to the local API.
- The closed notch doesn't show pins for now.
- No new home layout. Now playing stays as it is, and the bar is the customizable part.

### 7. Built-in: per-app volume
Per-app volume mixer in the notch. Needs a research spike on Core Audio process taps (macOS 14.2+) versus a virtual audio driver. Keep it isolated from upstream files.

### 8. Built-in: now playing
Already provided by Boring Notch. Keep it, and keep its compact layout.

## Order of work

1. Build the snapshot and run it on the notch-less MacBook Air and an external monitor. Record what works.
2. Quit in the context menu (item 0).
3. Compact-only (item 1) together with the expandable panel mechanism (item 2) and the calendar and mirror panels.
4. Adopt the non-notch clock (#1718) and the Bluetooth banner (#1668), after comparing with DynamicNotch and MewNotch (items 4 and 5).
5. Check the lock-screen click-swallow bug and add the locked-state skeleton (item 3, first pass only).
6. Raycast research spike, then the bridge (item 6).
7. Lock-screen settings tab (item 3, full), once Raycast content exists.
8. Per-app volume (item 7).

## Not goals

- A closed-source or paid release. The project is GPL-3.0.
- Feature parity with every Boring Notch option. Removing settings we don't need is fine.
