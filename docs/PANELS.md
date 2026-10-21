# Notch panels

VISION.md items 1 and 2: compact is the only layout, and features open as panels that grow the notch.

## Layout

The open notch is one black `NotchShape` holding two rows:

1. **Header** (`NotchPanelHeader`). On a notched display it sits either side of the camera cutout. On a non-notch display it is a short bar with no gap in the middle. The leading side has the settings gear first, then one button per available feature panel. The trailing side has the battery, or the open-notch OSD while one is showing. Clicking the active panel's button again goes back to home.
2. **Panel content.** Home (music, `CompactHomeView`) is the default. Calendar, Mirror and Shelf are the built-in feature panels.

A notification that is open replaces both rows with its reply UI, as before.

## `NotchPanel`

`components/Notch/NotchPanel.swift`:

- `NotchPanelID` is a string-backed identifier. It's an extensible struct rather than an enum so that Raycast-provided panels can register later.
- `NotchPanel` holds the id, title, SF Symbol, `isAvailable`, `preferredSize(vm)`, activate/deactivate hooks and a content builder.
- `NotchPanelSize` holds a width and an optional height. A `nil` height means the host measures the content's ideal height. Home uses this so its transport row can never fall outside the hover region (see the comment on `openNotchHeight` in `ContentView`).
- `NotchPanels.builtIn` is the registry. To add a panel, add an entry there.

Sizes are content sizes, without the shape's side and bottom padding. The host clamps them to `maxOpenNotchSize` (`sizing/matters.swift`), which also sets the fixed window size. It also floors the width so the header's buttons fit beside the real cutout.

| Panel | Size |
|---|---|
| Home | 336 wide, measured height |
| Calendar | 360 × 220 |
| Mirror | 200 tall, width from the camera's aspect ratio (square when the mirror shape is a circle) |
| Shelf | 480 × 130 |

## State

`BoringViewModel.activePanel` is kept per display. `open(panel:)` chooses the starting panel. That is home, or the shelf when it has files and "open shelf by default" is on, or whatever the caller asks for, such as a drag entering the notch. `showPanel(_:)` switches panels and runs the activate/deactivate hooks. The mirror uses these hooks to start and stop the camera, and `close()` still always stops it.

## Morph

The panel host is a single top-aligned `ZStack` whose frame is the target panel's size. `showPanel` runs inside `withAnimation(StandardAnimations.panelMorph)`, so the frame, and with it the black background and clip shape, springs continuously from one size to the next. Each panel's content keeps its own size and only fades in or out inside the shape. There's never a second window or a second shape.

## Hit-testing and closing

- `.onHover` is attached to the notch's laid-out frame. That frame jumps to the target size at the start of the spring, so the hover region always matches where the notch is going.
- AppKit doesn't always send a hover exit when a view shrinks out from under a pointer that isn't moving. So after each panel change, `reconcileHover()` compares the pointer with the measured notch frame (`vm.notchFrameSize`, centred at the top of the screen, which is how the window is placed on both notched and non-notch displays) and passes the result to `handleHover`. A pointer left outside after a collapse goes through the same 350 ms hover-exit grace and close path as any other exit, and popovers and sharing still block the close.
