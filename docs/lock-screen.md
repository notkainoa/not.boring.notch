# Lock screen

Notes on how the notch behaves while the Mac is locked, written for the first pass on VISION item 3. Research done 2026-10-21 against our `main` at `d427008` and upstream PR [#1346](https://github.com/TheBoredTeam/boring.notch/pull/1346) (head of `pull/1346/head`, last updated 2026-07-16, author TemujinCalidius).

Everything in this area depends on undocumented behaviour: the lock notifications, the SkyLight space and the CGS space. It is the likeliest part of the app to break on a new macOS release.

## How locked and unlocked are detected

`AppDelegate.applicationDidFinishLaunching` (`boringNotch/boringNotchApp.swift`) observes two distributed notifications:

- `com.apple.screenIsLocked` → `AppDelegate.onScreenLocked` → `NotchWindowManager.screenLocked()`
- `com.apple.screenIsUnlocked` → `AppDelegate.onScreenUnlocked` → `NotchWindowManager.screenUnlocked()`

These names are not public API, but every lock-screen utility uses them and they have been stable for years. Things to know:

- They fire for the lock screen (⌃⌘Q, lid close with "require password", screensaver with password, fast user switching away). A sleep/wake with no password required sends neither, so lock state can't get stuck from that path, but a missed unlock would leave the app thinking it is locked.
- There is no "current state" query in that API. Before this pass the app assumed "unlocked" at launch. The public `CGSessionCopyCurrentDictionary()` exposes `CGSSessionScreenIsLocked`, which can seed and re-check the state.
- Before this pass the state lived in `NotchWindowManager.isScreenLocked`, which only the window manager could read. Views had no way to know the screen was locked.

## How the SkyLight window works

The notch window is `BoringNotchSkyLightWindow` (`components/Notch/BoringNotchSkyLightWindow.swift`), a borderless, non-activating `NSPanel` at `.mainMenu + 3`, transparent, `canJoinAllSpaces`. Its content view is an `NSHostingView` of `ContentView`. The window is much larger than the drawn notch (`windowSize`, 640 wide), so most of it is transparent margin. Clicks in the margin reach the desktop because the window server skips fully transparent pixels of a non-opaque window.

Two private-API layers decide where the window lives:

1. **Our CGS space** (`private/CGSSpace.swift`, `managers/NotchSpaceManager.swift`). At launch we create one CGS space at the maximum absolute level and add every notch window to it (`notchSpace.windows.insert`). That keeps the notch above full-screen apps and out of Mission Control. `CGSSpace.windows` is a `Set` whose `didSet` adds/removes the diff at the window-server level, so it only talks to the server when the Swift set changes.
2. **The SkyLight space** (Swift package `SkyLightWindow` by Lakr233, `SkyLightOperator`). At first use it creates a space with `SLSSpaceCreate` and sets it to absolute level 400 (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`), which is drawn above the lock screen. `delegateWindow` calls `SLSSpaceAddWindowsAndRemoveFromSpaces(cid, space, [wid], 7)`. Flag 7 **removes the window from every space it is in, including our CGS notch space**, and adds it to the SkyLight space.

Our extension `SkyLightOperator.undelegateWindow` (same file as the window) only calls `SLSRemoveWindowsFromSpaces(cid, [wid], [skylightSpace])`.

On lock, with `Defaults[.showOnLockScreen]` on, `NotchWindowManager.screenLocked()` calls `enableSkyLight()` on the notch window(s). On unlock, `screenUnlocked()` waits 150 ms (to avoid a flicker during the unlock transition) and calls `disableSkyLight()`. With the setting off, lock closes every notch window and unlock rebuilds them, so SkyLight is never used.

## What is shown while locked (before this pass)

With `showOnLockScreen` on, the same window and the same `ContentView` are moved to the SkyLight space, so the whole notch behaves exactly as it does when unlocked:

- Closed state: music live activity (album art, spectrum, inline song-change peek showing the track title), notification live activity (sender and message text), battery/charging notice, OSD (volume/brightness), the idle face.
- Hover, tap, gestures and the keyboard shortcut open the notch. The open notch shows the home view with album art, track title, controls, calendar events and the mirror (which turns the camera on), or the shelf with its files. An active notification opens its reply UI.
- Right-click opens the context menu (Settings).
- Global drag detectors stay active and can open the shelf.

In short, everything private is visible and reachable from the lock screen.

## The click-swallow bug

Reported in #1346: after an unlock, the SkyLight-touched notch window's transparent margins start swallowing desktop clicks under and near the notch (menu bar items, tabs and toolbar buttons just under the menu bar). The author tried undelegating, re-adding the window to the high-level notch space, and moving it to the active space. None of those fixed it reliably. Only replacing the window with a brand-new one (new window number, never delegated to SkyLight) did.

### Does our code have it?

Very likely yes, though it can't be confirmed without locking a real machine. Our lock path is byte-for-byte the code #1346 was written against:

- The same `delegateWindow` (flag 7) and the same `undelegateWindow`.
- After `undelegateWindow` the window is in **no CGS space at all**: flag 7 took it out of the notch space, and nothing puts it back, because `notchSpace.windows` still contains it and `didSet` never fires. A freshly created window is in the notch space. So even setting the server-side SkyLight state aside, the window after unlock is provably not in the state a fresh window is in.
- The window is never replaced on unlock. It keeps living until a display change or a display-mode change rebuilds it, which matches the report that the bug persists until something recreates the window.

### How #1346 fixes it

After the unlock morph, `seamlesslyRebuildNotchWindows` swaps each window for a fresh one:

1. Create a bare `BoringNotchSkyLightWindow` at the same position without installing a new `NSHostingView`. A new hosting view would show a blank first frame and restart the audio spectrum's phase and the album-art `matchedGeometryEffect`.
2. Put a `NotchPassthroughContainerView` in it (an `NSView` whose `hitTest` never returns itself, so margins still pass clicks through), add a static bitmap snapshot of the live view, order the new window front and flush.
3. Move the **same** live `NSHostingView` into the container above the snapshot and flush. The snapshot covers the sub-frame gap while the moved layer re-hosts asynchronously.
4. One run-loop turn later, order out and close the old window and remove the snapshot.

It also re-adds the window to the notch space after undelegating (`CGSSpace.reassert`) and swaps the window after a wake that wasn't preceded by an unlock.

## What to take from #1346

| Part | Take? | Notes |
|---|---|---|
| Window swap via reparenting the live hosting view, bridged by a snapshot | **Yes** | The actual click-swallow fix. Adapted into `NotchWindowManager` rather than copied. |
| `NotchPassthroughContainerView` | **Yes** | Needed so the container doesn't change click-through. |
| `CGSSpace.reassert` after undelegating | **Yes** | Cheap, and restores the CGS membership the window should have between unlock and the swap. Not enough on its own, per the PR. |
| Locked flag on a shared model that gates `open()`, hover, gestures and drags | **Yes, as an idea** | Ours is `BoringViewCoordinator.isScreenLocked`, plus a per-feature policy instead of #1346's hardcoded "everything private". |
| `ignoresMouseEvents` on the notch windows while locked | **Yes** | Stops hover, clicks, the context menu and gestures over the lock screen without touching `ContentView`. |
| Closing an open notch on lock and tearing down drag detectors | **Yes** | |
| Padlock that morphs open on unlock (`UnlockAnimation`, `lockedNotchContent`) | **Not now** | Nice, but it's UI on top of the compact layout that another thread is rewriting. Revisit with the lock-screen settings tab. |
| Showing the notch over the lock screen even when `showOnLockScreen` is off (the "lock showcase") | **No** | Our setting stays the single switch. |
| Treating the track title and album art as always private | **No** | Replaced by the user-configurable policy. Music is visible by default. |
| The 2.4 s swap delay tied to the animation | **No** | Without the morph we swap right after SkyLight is disabled. |
| Wake safety net | **Partly** | We re-check the real lock state (`CGSessionCopyCurrentDictionary`) on wake instead of assuming. |
