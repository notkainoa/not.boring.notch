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

## Our implementation (first pass)

### Lock state

`BoringViewCoordinator.isScreenLocked` (published, main actor) is the one place that knows the screen is locked. Only `NotchWindowManager` sets it (`setScreenLocked`), from the lock/unlock notifications. It also seeds it at launch and re-checks it on wake and when the user session becomes active again, using `CGSessionCopyCurrentDictionary` (`private/SessionLockState.swift`, undocumented key). Views read it through the coordinator they already observe.

### Lock-screen policy

`models/LockScreenPolicy.swift`:

- `LockScreenFeature`: `music`, `battery`, `notifications`, `calendar`, `shelf`, `mirror`.
- `LockScreenVisibility`: `visible` or `hidden`. A `redacted` case for calendar titles and shelf names can be added later without changing storage.
- One `Defaults` key per feature in `Constants.swift` (`lockScreenMusicVisibility` and so on). Defaults: music and battery visible; notifications, calendar, shelf and mirror hidden.
- `LockScreenFeature.visibilityKey` maps each feature to its key, so a settings row is `@Default(feature.visibilityKey)` or a `Picker` over `LockScreenVisibility.allCases`.
- `BoringViewCoordinator.isVisible(_ feature:)` answers "may this feature show right now": always true when unlocked, the policy value when locked.

### What locked means in this pass

- The notch can't open while locked (`BoringViewModel.open()` refuses, which covers hover, tap, gestures, the shortcut and drags), any open notch is closed on lock, the notch windows ignore the mouse and drag detectors are torn down. The open views (home with calendar and mirror, shelf, notification reply) are therefore never reachable while locked, whatever the policy says. When expandable panels exist, the policy decides which panels may open while locked.
- Closed-state activities follow the policy: the music live activity and music sneak peeks (`music`), the battery/charging notice (`battery`) and notification live activities (`notifications`). OSDs and the idle face are not private and always show.
- Nothing changes when `showOnLockScreen` is off: the windows are still destroyed on lock.
- Policy checks happen where things are presented: `BoringViewCoordinator.toggleSneakPeek` and `toggleExpandingView` drop hidden alerts, `setScreenLocked(true)` clears hidden ones already on screen, and `ContentView.liveActivities` filters the music and notification activities. All of them short-circuit when unlocked, so there's no cost at rest.

### Hook points

For whoever reworks these files (the compact-only `ContentView` rewrite in particular):

- `ContentView.liveActivities`: `coordinator.isVisible(.notifications)` and `coordinator.isVisible(.music)`.
- `ContentView` body, open content: `vm.notchState == .open && !coordinator.isScreenLocked`. A notch held open by a share picker on lock must not draw private content.
- `BoringViewModel.open()`: refuses while locked.
- `BoringViewCoordinator`: `isScreenLocked`, `setScreenLocked`, `isVisible(_:)`, and the guards at the top of `toggleSneakPeek` and `toggleExpandingView`.
- `NotchWindowManager`: `screenLocked`, `screenUnlocked`, `resyncLockState`, `leaveLockScreen`, `replaceSkyLightDelegatedWindows`, and `makeNotchWindow` (applies SkyLight and `ignoresMouseEvents` for the current lock state).
- `AppDelegate`: lock/unlock observers plus wake and session-active observers that call `resyncLockState`.

### Click-swallow fix

`NotchWindowManager.leaveLockScreen` disables SkyLight 150 ms after unlock (as before; `disableSkyLight` now also re-adds the window to the notch space), waits another 150 ms, then replaces every window that was ever delegated to SkyLight (`BoringNotchSkyLightWindow.wasDelegatedToSkyLight`) with a fresh window, moving the same hosting view across behind a snapshot. The pending unlock work is cancelled if the screen locks again first. Windows created while locked (for example after a display change) are delegated too, so they get replaced the same way.

This is unverified on a real lock screen. The bug's existence in our code is established by reading the code, not by reproducing it.

## Manual test checklist

Do these on the M1 MacBook Air (no notch), then repeat the starred items on a notched Mac or with an external display in "all displays" mode. Settings → Notch → "Show notch on lock screen" must be on unless a step says otherwise.

1. **Baseline click-through (before locking).** Note something clickable right under the notch area, e.g. a Safari tab or toolbar button 20–60 px below the menu bar and up to ~300 px either side of the centre. Click it a few times to confirm it works.
2. **Lock while idle.** Lock with ⌃⌘Q. The notch should appear over the lock screen. Hovering it must not open it; right-clicking must not show the menu.
3. **Music while locked.** Start music, then lock. The closed music activity should show. Skip a track with the media keys: the song-change peek should show.
4. **Notifications while locked.** Trigger a notification while locked (e.g. send yourself an iMessage from another device). No notification activity should appear in the notch.
5. **Battery while locked.** Plug in or unplug the charger while locked. The charging notice should show.
6. **Lock while open.*** Open the notch (hover), keep the pointer there and press ⌃⌘Q. The notch should be closed on the lock screen.
7. **Unlock, then click-through.*** Unlock and, within a second or two, click the same targets from step 1 repeatedly, including directly under either side of the notch. Every click must land. This is the click-swallow check. Before this branch, these clicks were expected to be swallowed.
8. **Unlock continuity.*** With music playing, unlock and watch the notch: there should be no blank frame or visible flash when the window is swapped (a 1–2 px seam at the top edge for one frame is the known #1346 tradeoff).
9. **Notch still works after unlock.*** Hover to open, use the music controls, open the shelf by dragging a file onto the notch, open Settings from the right-click menu, and type in any notch text field (e.g. a notification reply). All must behave as before.
10. **Rapid lock/unlock.** Lock and unlock three times in quick succession (unlock within ~1 s). The notch must end up visible and working (step 9), and step 7 must still pass.
11. **Display change while locked.*** Plug or unplug an external display while locked, then unlock. Repeat steps 7 and 9.
12. **Setting off.** Turn "Show notch on lock screen" off and lock. No notch over the lock screen. Unlock: the notch comes back and steps 7 and 9 pass.
13. **Sleep without lock.** With "Require password" set to a delay (or off), close the lid briefly and reopen without a password prompt. The notch must open on hover normally.
14. **Policy override (no UI yet).** Quit the app, run `defaults write theboringteam.boringnotch lockScreenMusicVisibility -string hidden`, relaunch, and repeat step 3: no music activity or song-change peek while locked, and music shows again after unlock. Undo with `defaults delete theboringteam.boringnotch lockScreenMusicVisibility`. The same works for `lockScreenBatteryVisibility` and `lockScreenNotificationsVisibility` (`visible`/`hidden`).
