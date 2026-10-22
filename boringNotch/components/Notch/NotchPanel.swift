//
//  NotchPanel.swift
//  boringNotch
//
//  The open notch shows one panel at a time: home (now playing) by default,
//  or a feature panel picked from the header. Each panel declares the size
//  it wants and the notch springs to it, so adding a panel (Raycast content
//  later) means adding an entry to NotchPanels.builtIn and nothing else.
//  See docs/PANELS.md.
//

import Defaults
import SwiftUI

/// String-backed rather than an enum so panels that aren't built in (for
/// example ones Raycast provides) can be identified the same way.
struct NotchPanelID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let home = NotchPanelID(rawValue: "home")
    static let calendar = NotchPanelID(rawValue: "calendar")
    static let mirror = NotchPanelID(rawValue: "mirror")
    static let shelf = NotchPanelID(rawValue: "shelf")
}

/// Content size, without the notch shape's side and bottom padding.
struct NotchPanelSize: Equatable {
    var width: CGFloat
    /// nil sizes the panel to its content's ideal height, which the host
    /// measures. Use it for content whose height isn't known up front.
    var height: CGFloat?
}

/// What a panel's content can draw on that lives in ContentView.
struct NotchPanelContext {
    let vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    let isHoveringMusicArea: Binding<Bool>
}

@MainActor
struct NotchPanel: Identifiable {
    let id: NotchPanelID
    let title: LocalizedStringResource
    let systemImage: String
    /// Whether the user has the panel turned on. A panel that's off can't
    /// be shown; switching to it lands on home.
    var isAvailable: () -> Bool = { true }
    /// Whether the hardware the panel needs is there. Only hides the
    /// header button: an active panel stays put when its hardware goes
    /// away, so it can show that and pick up again when it comes back.
    var hasHardware: (BoringViewModel) -> Bool = { _ in true }
    var preferredSize: (BoringViewModel) -> NotchPanelSize
    var onActivate: (BoringViewModel) -> Void = { _ in }
    var onDeactivate: (BoringViewModel) -> Void = { _ in }
    var content: (NotchPanelContext) -> AnyView
}

@MainActor
enum NotchPanels {
    static let home = NotchPanel(
        id: .home,
        title: "Now Playing",
        systemImage: "music.note",
        preferredSize: { _ in NotchPanelSize(width: 336, height: nil) },
        content: { context in
            AnyView(
                CompactHomeView(
                    albumArtNamespace: context.albumArtNamespace,
                    horizontalMediaGestureFeedback: context.horizontalMediaGestureFeedback
                )
                .onHover { context.isHoveringMusicArea.wrappedValue = $0 }
                .onDisappear { context.isHoveringMusicArea.wrappedValue = false }
            )
        }
    )

    static let calendar = NotchPanel(
        id: .calendar,
        title: "Calendar",
        systemImage: "calendar",
        isAvailable: { Defaults[.showCalendar] },
        // Room for the date strip plus four or five event rows.
        preferredSize: { _ in NotchPanelSize(width: 360, height: 210) },
        content: { context in
            AnyView(
                CalendarView()
                    // The event list scrolls, so an upward swipe there is a
                    // scroll, not the close gesture.
                    .onHover { context.vm.isHoveringCalendar = $0 }
                    .onDisappear { context.vm.isHoveringCalendar = false }
            )
        }
    )

    static let mirror = NotchPanel(
        id: .mirror,
        title: "Mirror",
        systemImage: "web.camera",
        isAvailable: { Defaults[.showMirror] },
        // No button on a Mac without a camera: the panel would be empty.
        hasHardware: { vm in vm.camera.cameraAvailable },
        preferredSize: { vm in
            let size = mirrorPreviewSize(vm)
            return NotchPanelSize(width: size.width, height: size.height)
        },
        // The camera only runs while this panel is showing. close() also
        // stops it, whichever panel is up.
        onActivate: { vm in vm.startCameraPreview() },
        onDeactivate: { vm in vm.camera.stopSession() },
        content: { context in
            // The panel can end up wider than the preview (the header
            // needs room beside a real cutout), so the preview keeps its
            // own size and sits centred instead of stretching.
            let size = mirrorPreviewSize(context.vm)
            return AnyView(
                CameraPreviewView(camera: context.vm.camera)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity)
            )
        }
    )

    /// The camera's aspect ratio, or a square for the circle shape.
    private static func mirrorPreviewSize(_ vm: BoringViewModel) -> CGSize {
        let height: CGFloat = 190
        guard Defaults[.mirrorShape] == .rectangle else {
            return CGSize(width: height, height: height)
        }
        return CGSize(width: (height * vm.camera.videoAspectRatio).rounded(), height: height)
    }

    static let shelf = NotchPanel(
        id: .shelf,
        title: "Shelf",
        systemImage: "tray.fill",
        isAvailable: { Defaults[.boringShelf] },
        preferredSize: { _ in NotchPanelSize(width: 480, height: 130) },
        content: { context in
            AnyView(
                ShelfView(
                    dropInteraction: context.vm.dropInteraction,
                    animation: context.vm.animation
                )
            )
        }
    )

    /// Header order. Home comes first but gets no button: clicking the
    /// active panel's button again is how you get back to it.
    static let builtIn: [NotchPanel] = [home, calendar, mirror, shelf]

    static func panel(for id: NotchPanelID) -> NotchPanel? {
        builtIn.first { $0.id == id }
    }

    /// Buttons shown in the header. The active panel always keeps its
    /// button, since clicking it again is the way back to home.
    static func featurePanels(for vm: BoringViewModel) -> [NotchPanel] {
        builtIn.filter { panel in
            panel.id != .home && panel.isAvailable()
                && (panel.hasHardware(vm) || panel.id == vm.activePanel)
        }
    }
}

// MARK: - Geometry

@MainActor
enum NotchPanelLayout {
    /// Padding ContentView puts between the notch shape and its content:
    /// the opened top corner radius plus 12 on each side, and 12 below.
    static var horizontalChrome: CGFloat { 2 * (cornerRadiusInsets.opened.top + 12) }
    static let bottomChrome: CGFloat = 12
    /// NotchLayout's VStack spacing between the header and the panel.
    static let headerSpacing: CGFloat = 8

    static func headerHeight(hasNotch: Bool, closedNotchHeight: CGFloat) -> CGFloat {
        // Beside a real cutout the header has to line up with it. Without
        // one it's a short bar: tall enough for the buttons, no taller.
        hasNotch ? max(NotchPanelHeader.minimumHeight, closedNotchHeight) : NotchPanelHeader.minimumHeight
    }

    /// The largest content any panel gets. Derived from the window size so
    /// a panel can never be drawn past the window's edge.
    static func maximumContentSize(headerHeight: CGFloat) -> CGSize {
        CGSize(
            width: maxOpenNotchSize.width - horizontalChrome,
            height: maxOpenNotchSize.height - headerHeight - headerSpacing - bottomChrome
        )
    }

    /// The panel's preferred size, widened so the header fits beside the
    /// cutout and clamped to the window.
    static func contentSize(
        for panel: NotchPanel,
        vm: BoringViewModel,
        headerHeight: CGFloat
    ) -> NotchPanelSize {
        var size = panel.preferredSize(vm)
        let maximum = maximumContentSize(headerHeight: headerHeight)
        let cutout = vm.hasNotch ? vm.closedNotchSize.width : 0
        let sideWidth = NotchPanelHeader.leadingWidth(panelCount: NotchPanels.featurePanels(for: vm).count)
        let headerMinimum = cutout + 2 * sideWidth - 2 * NotchPanelHeader.edgeOverhang
        size.width = min(max(size.width, headerMinimum), maximum.width)
        if let height = size.height {
            size.height = min(height, maximum.height)
        }
        return size
    }
}
