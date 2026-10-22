# Bluetooth alert notes: #1668 vs DynamicNotch vs MewNotch

Written 2026-10-21 while adopting upstream PR #1668. This is a reference comparison, not a design doc.

Reference code was read from shallow clones in `/tmp` and never built or run:

- DynamicNotch (`jackson-storm/DynamicNotch`, GPL-3.0), commit `8c4d423` (2026-10-18). Its Bluetooth code is under `DynamicNotch/Features/Bluetooth/`. Its alert plumbing is `Features/Network/WiFi/EventHandlers/NotchConnectivityEventsHandler.swift` and `Core/NotchEngine/`.
- MewNotch (`monuk7735/mew-notch`, GPL-3.0), commit `8377111` (v2.4.0). **It has no Bluetooth feature at all.** A case-insensitive search for `bluetooth`, `wifi`, `vpn` and `airpods` finds nothing. The closest thing is its audio-output-device HUD (a default-output-device change shows the device name for 1 s). It is useful only as a model for HUD timing and lock-screen gating.

Nothing was copied from either project. If we later reuse code, keep the GPL-3.0 attribution and add it to `THIRD_PARTY_LICENSES/`.

## What #1668 does

Files: `managers/BluetoothAccessoryManager.swift`, `components/LiveActivities/BluetoothAccessoryView.swift`, plus a few hook points.

- **Detection.** `IOBluetoothDevice.register(forConnectNotifications:selector:)` is the only trigger. Each connect callback registers a per-device `register(forDisconnectNotification:selector:)`. There is no polling and no power-state handling.
- **Already-connected devices.** The author assumes IOBluetooth replays a connect callback for each already-connected device right after registration. `start()` sets `ignoreConnectionsUntil = now + 2s` so those replays don't show banners but still register their disconnect observers.
- **Battery.**
  - First try: KVC on `IOBluetoothDevice` using the private properties `batteryPercentSingle`, `batteryPercentLeft`, `batteryPercentRight` and `batteryPercentCase`. Each is guarded by `responds(to:)` and range-checked to 1...100.
  - Fallback: IORegistry. It walks `AppleDeviceManagementHIDEventService` and matches `DeviceAddress`, then reads `BatteryPercent`. This covers Magic Keyboard, Mouse and Trackpad.
  - Refresh: re-read at +1 s and +2.5 s after connect, and re-show the banner if the value changed.
- **Permissions.** Sandbox entitlement `com.apple.security.device.bluetooth` plus `NSBluetoothAlwaysUsageDescription`. It is opt-in (`showBluetoothAccessories`, default off), so the prompt only appears once the user enables it. The usage string is in the built Info.plist (checked with PlistBuddy). The entitlement is in `boringNotch.entitlements`, but the unsigned build can't show it embedded.
- **Presentation.** A new `SneakContentType.bluetooth` is raised through `BoringViewCoordinator.toggleExpandingView`. `ContentView` renders `BluetoothAccessoryView` in the closed notch with the same layout as the power notice: icon and name on the left, a black spacer the width of the notch, battery or "Connected" or "Disconnected" on the right. The shared `expandingView` timer hides it after 3 s. The notch widens to 640 pt.

## DynamicNotch

- **Detection.** Layered:
  - IOBluetooth connect and disconnect notifications. Disconnect observers are registered up front for every paired device.
  - CoreAudio property listeners on the device list and the default output device.
  - A 3 s polling timer (5 s tolerance) that diffs `pairedDevices().filter(isConnected)` against what it knows, and also checks `IOBluetoothHostController.powerState`.
  - An explicit `checkInitialDevices()` at launch, so devices already connected at launch don't depend on callback replay.
- **Scope.** It only alerts for audio devices. It uses a keyword list, SDP service records 0x110B, 0x1108 and 0x111E, and the class-of-device major class. Keyboards and mice are ignored. Only **connect** events produce an alert. Disconnects just update state.
- **Battery.** Many sources, merged:
  - IORegistry (`AppleDeviceManagementHIDEventService` and `IOHIDEventService`, trying several `Battery*` keys).
  - `/Library/Preferences/com.apple.Bluetooth` DeviceCache, via `UserDefaults(suiteName:)`.
  - `pmset -g accessories`.
  - `system_profiler SPBluetoothDataType`.
  - A CoreBluetooth GATT read of the Battery Service (0x180F, characteristic 0x2A19).
  - Retries at 0.4, 0.8 and 1.2 s after connect while the level is still nil, and a 5 s cooldown on the `pmset` fallback.
- **Permissions.** Its app is **not sandboxed** (`ENABLE_APP_SANDBOX = NO`), which is what allows `pmset`, `system_profiler` and reading `/Library/Preferences`. It has the `NSBluetoothAlwaysUsageDescription` Info.plist key. Settings has a Bluetooth permission row that shows `CBManager.authorization` and triggers the prompt with a throwaway `CBCentralManager`. It opens the Privacy pane if access was denied.
- **Presentation.** Bluetooth is a "temporary notification" content object. It carries a priority, a size and a corner radius. It has two styles (compact icon plus circle or percent, or a taller detailed card), an optional battery-coloured stroke, and a user-set duration. Wi-Fi and VPN go through the same engine: no-internet is a persistent notification, and hotspot and VPN are live activities that can be hidden later by id.
- **Undocumented API.** None for the battery read. It uses only public IOBluetooth, IOKit and CoreBluetooth calls plus the CLI tools above.

## MewNotch (HUD and lock-screen model only)

- Alerts are optional `HUDPropertyModel` values on the notch view model (icon, name, value, timeout, timer). They are shown by non-nil checks, and `resetHUDTimer` re-arms a per-HUD timer (default 1 s).
- Each HUD kind has its own enable setting, and each has its own lock-screen gate (`lockScreenShowAudioOutputHUD`, `lockScreenShowPowerHUD` and so on), checked in one `hasActiveHUD` property.
- The audio-device HUD fires from a CoreAudio default-output listener. That is the only connect-like alert it has, and it doesn't report battery.
- No Bluetooth entitlement or usage string. Its entitlements file has only camera and network-client, with no app-sandbox key.

## What #1668 gets wrong or misses

Items marked **(unverified)** could not be confirmed here. Bluetooth behavior needs real hardware.

1. **Devices already connected at launch (unverified).** The 2 s grace window assumes IOBluetooth replays connects quickly. There are two failure modes:
   - If the replay is slower than 2 s, which is plausible at login or while the permission prompt is open, existing devices show as new connections.
   - If IOBluetooth doesn't replay at all, already-connected devices never get a disconnect observer, so their disconnects are never announced.
   - DynamicNotch avoids both by seeding from `pairedDevices()` + `isConnected()` explicitly. We should do the same: seed a set of known-connected addresses at `start()` and drop the timer.
2. **Callback-only detection.** There is no power-state or sleep/wake handling and no polling or CoreAudio backstop. A missed notification means a missed alert. Bluetooth being toggled off or on, or sleep/wake, can also fire a burst of disconnects and then connects, because the Mac drops every link at once.
3. **Multiple devices.** There is a single `lastEvent`. A second connect within 3 s overwrites the first banner and cancels the first device's battery refresh. Nothing is queued. This is the case after wake, or when a keyboard and mouse reconnect together.
4. **Battery refresh timing.**
   - Two fixed re-reads (1 s and 2.5 s) are a guess. DynamicNotch retries at 0.4, 0.8 and 1.2 s and stops once it has a level.
   - There is no later refresh while the banner or device stays up, and no battery change events.
   - A level of 0 is treated as "unknown", so a genuinely empty battery shows "Connected".
   - A refresh re-raises the banner, which restarts the shared 3 s timer, so the banner can stay up for up to about 5.5 s.
5. **Private IOBluetooth selectors (unverified).** `batteryPercentSingle`, `batteryPercentLeft`, `batteryPercentRight` and `batteryPercentCase` are undocumented, so they can change in any macOS release. They are guarded with `responds(to:)`, so a rename degrades to "no battery" instead of crashing, but nothing logs the degradation. The notes in `docs/UPSTREAM-SYNC.md` already list these as a compatibility watch item. The `caseLevel` value is parsed but never shown.
6. **HID fallback under the sandbox (unverified).** Reading `AppleDeviceManagementHIDEventService` from a sandboxed app is not covered by the entitlement. The PR claims it works, but it needs checking on hardware. DynamicNotch can use `pmset`, `system_profiler` and DeviceCache because it isn't sandboxed, and we can't.
7. **No permission feedback.** There is no authorization check, no way to see that access was denied, and no link to the Privacy pane. DynamicNotch's `CBCentralManager` permission row is a working model. If the user denies access, the setting just does nothing.
8. **Scope.** All connected Bluetooth devices produce a banner, with no per-device or per-class filter. Phones, watches and other Continuity devices that connect often could be noisy (unverified). DynamicNotch filters to audio devices and has a user-set duration.
9. **Presentation.**
   - The left and right columns are a fixed 150 pt, so long names truncate.
   - Duration is the shared 3 s with no setting.
   - `BluetoothAccessoryView` is only wired into the closed-notch chain, so there is no lock-screen gating. MewNotch gates every HUD kind individually.
   - It only has the one `expandingView` slot, so it competes with the battery notice. Battery wins in `ContentView` ordering, but there is no queueing.
10. **Minor.** `stop()` clears `lastEvent` but not an already-visible banner, which `showBluetoothActivity` hides anyway because it checks the Defaults flag. The icon is picked from name substrings and the class of device, so third-party devices fall back to generic icons.

No small, clearly correct bug fix turned up. Items 1, 3 and 4 need design choices and hardware testing, so they are left for the generalization work below.

## Recommendation: generalize the pipeline later (not implemented)

Today each alert is a `SneakContentType` case plus a hand-written branch in `ContentView`: battery and Bluetooth both use the same "left label, notch-width spacer, right value" layout and the single 3 s `expandingView` timer in `BoringViewCoordinator`. That does not scale to Wi-Fi, VPN or Raycast.

1. **One alert model.** A value type such as `NotchAlert { id, kind, title, icon, trailing (text / battery / progress / none), tint, duration, priority, coalescingKey }`. Sources build alerts, and nothing else touches the view. Battery and Bluetooth become the first two sources, then Wi-Fi, VPN and Raycast.
2. **One `NotchAlertCenter`.** It holds the current alert plus a short queue. It dedupes by `coalescingKey` (same device updates in place, which fixes the battery-refresh and re-raise problem), orders by priority, and owns the timer. It replaces the `expandingView` timer for these cases. DynamicNotch's engine shows the shape (id, priority, stack id, persistent versus temporary), but it's much bigger than we need.
3. **One view slot.** `ContentView` gets one branch that renders `NotchAlertView(alert)`. The existing power notice and Bluetooth view collapse into it. This is the only `ContentView` hook, which suits the compact-only rewrite.
4. **Source boundary.** Each source is a small object that only emits alerts and exposes its own `Defaults` toggle. The Bluetooth manager would shrink to detection and battery reading, with seeding from `pairedDevices()`, a CoreAudio or polling backstop, and sleep/wake suppression added there.
5. **Persistent versus temporary.** Allow `duration == nil` plus `dismiss(id:)` for state alerts such as "no internet" or "VPN connected", like DynamicNotch's live-activity hide-by-id.
6. **Per-alert-kind lock-screen gating.** Use a single `isAllowedWhileLocked` check per kind, in the style of MewNotch's `hasActiveHUD`. This lines up with the deferred lock-screen settings work (VISION item 3).
7. **Wi-Fi and VPN sources.** Options to evaluate under the sandbox: `NWPathMonitor` for connectivity and interface type, `CWWiFiClient` event monitoring for Wi-Fi (reading the SSID needs Location permission on recent macOS), and `SCDynamicStore` for VPN interfaces. All of this needs checking against the sandbox on real machines.
8. **Raycast.** Raycast-driven alerts then just construct a `NotchAlert` from the bridge payload. Whatever transport VISION item 6 picks only has to deserialize into `NotchAlert` and call `NotchAlertCenter.post(_:)`. Needs a per-sender or per-kind allow list, since it is an external input.
