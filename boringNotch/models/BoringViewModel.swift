//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

final class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?
    let dropInteraction = DropInteractionState()

    @Published private(set) var notchState: NotchState = .closed

    var cancellables: Set<AnyCancellable> = []

    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    /// Keeps the open notch alive while a popover is showing.
    @Published var isPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    /// Which panel the open notch shows. Per display, since each display's
    /// notch has its own geometry. Read it through `currentPanel`, which
    /// falls back to home if this panel was turned off in Settings.
    @Published private(set) var activePanel: NotchPanelID = .home
    /// The notch shape's laid-out size, reported by ContentView whenever its
    /// layout changes. Not published: it's only read to hit-test the
    /// pointer, and publishing it would re-render the notch for nothing.
    var notchFrameSize: CGSize = .zero

    let camera: CameraModel

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil, camera: CameraModel) {
        animation = animationLibrary.animation
        self.camera = camera
        self.screenUUID = screenUUID

        super.init()

        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        setupDetectorObserver()
        setupPanelAvailabilityObserver()
    }

    /// Turning off the panel that's showing would otherwise only hide it:
    /// currentPanel falls back to home, but the panel's onDeactivate never
    /// runs, so the mirror's camera would keep going.
    private func setupPanelAvailabilityObserver() {
        Defaults.publisher(keys: .showCalendar, .showMirror, .boringShelf, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.leaveUnavailablePanel() }
            .store(in: &cancellables)
    }

    private func leaveUnavailablePanel() {
        guard activePanel != .home,
              let panel = NotchPanels.panel(for: activePanel),
              !panel.isAvailable() else { return }
        panel.onDeactivate(self)
        withAnimation(StandardAnimations.panelMorph) {
            activePanel = .home
        }
        if notchState == .open {
            NotchPanels.home.onActivate(self)
        }
    }

    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    /// Whether the current screen has a notch (safe area top inset > 0)
    var hasNotch: Bool {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return (currentScreen?.safeAreaInsets.top ?? 0) > 0
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    /// Starts the mirror without the stop half of the old toggle. Opening
    /// the mirror panel calls this, and tapping the preview still toggles.
    /// Denied access doesn't prompt here: the panel shows "Access Denied"
    /// and tapping it explains how to fix that.
    func startCameraPreview() {
        switch camera.state {
        case .stopped, .unavailable, .failed:
            if camera.cameraAvailable {
                camera.startSession()
            }
        case .permissionRequired:
            camera.requestAccess()
        case .running, .interrupted, .permissionDenied, .requestingPermission, .starting:
            break
        }
    }

    func toggleCameraPreview() {
        switch camera.state {
        case .running, .interrupted:
            camera.stopSession()
        case .stopped, .unavailable, .failed:
            if camera.cameraAvailable {
                camera.startSession()
            }

        case .permissionDenied:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Camera Access Required", comment: "Camera permission alert title")
                alert.informativeText = NSLocalizedString("Please allow camera access in System Settings.", comment: "Camera permission alert message")
                alert.addButton(withTitle: NSLocalizedString("Open Settings", comment: "Button title that opens app or system settings"))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button title"))

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .permissionRequired:
            camera.requestAccess()

        case .requestingPermission, .starting:
            break
        }
    }

    /// Whether the pointer is over the notch shape as currently laid out.
    /// The window sits top-centre on its screen with or without a notch,
    /// and the shape sits top-centre in the window, so the shape's screen
    /// rect follows from its size alone.
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let frame = getScreenFrame(screenUUID), notchFrameSize != .zero else { return false }
        let rect = CGRect(
            x: frame.midX - notchFrameSize.width / 2,
            y: frame.maxY - notchFrameSize.height,
            width: notchFrameSize.width,
            height: notchFrameSize.height
        )
        return rect.contains(position)
    }

    var currentPanel: NotchPanel {
        if let panel = NotchPanels.panel(for: activePanel), panel.isAvailable() {
            return panel
        }
        return NotchPanels.home
    }

    /// Opens the notch on `panel`, or on the default panel when nil. If the
    /// notch is already open, switches to `panel` instead. Returns whether
    /// the notch went from closed to open.
    @discardableResult
    func open(panel: NotchPanelID? = nil) -> Bool {
        guard !coordinator.firstLaunch else { return false }
        guard notchState != .open else {
            if let panel { showPanel(panel) }
            return false
        }

        setActivePanel(panel ?? defaultPanel)
        self.notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()

        return true
    }

    /// Switches the open notch to another panel. Wrap in an animation to
    /// morph the shape; ContentView uses StandardAnimations.panelMorph.
    func showPanel(_ id: NotchPanelID) {
        guard notchState == .open else { return }
        setActivePanel(id)
    }

    private func setActivePanel(_ id: NotchPanelID) {
        // A panel that's been turned off (or a stale id) lands on home.
        let next = NotchPanels.panel(for: id).flatMap { $0.isAvailable() ? $0 : nil } ?? NotchPanels.home
        let previous = currentPanel
        guard previous.id != next.id || notchState == .closed else { return }
        if previous.id != next.id {
            previous.onDeactivate(self)
        }
        activePanel = next.id
        next.onActivate(self)
    }

    /// The shelf when it has files and the user asked for it, otherwise home.
    private var defaultPanel: NotchPanelID {
        if Defaults[.boringShelf] && !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            return .shelf
        }
        return .home
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        // The camera is on-demand: the notch closing always ends capture.
        // Intent clears too, so no recovery path can reopen it while closed.
        camera.stopSession()
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isPopoverActive = false
        if self.coordinator.shouldShowSneakPeek(on: self.screenUUID) {
            self.coordinator.toggleSneakPeek(status: false, type: .music, targetScreenUUID: self.screenUUID)
        }
        self.edgeAutoOpenActive = false
        // The panel isn't reset here: the open content is still on screen
        // during the close animation. open() picks the next panel.
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
