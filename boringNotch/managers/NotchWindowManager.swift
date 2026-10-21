//
//  NotchWindowManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Extracted from AppDelegate: all notch-window, per-screen view-model and
//  drag-detector lifecycle in one place. AppDelegate keeps app-lifecycle
//  glue (shortcuts, onboarding, termination) and forwards to this manager.
//

import Defaults
import SwiftUI

@MainActor
final class NotchWindowManager {
    /// All per-screen state in one value — replaces the parallel
    /// windows/viewModels/dragDetectors dictionaries that previously had
    /// to be mutated in lockstep (a missed mutation leaked observers).
    struct ScreenContext {
        let viewModel: BoringViewModel
        var window: NSWindow?
        var dragDetector: DragDetector?
    }

    private(set) var contexts: [String: ScreenContext] = [:] // UUID -> ScreenContext
    private(set) var primaryWindow: NSWindow?
    let primaryViewModel: BoringViewModel
    private var primaryDragDetector: DragDetector?

    private(set) var isScreenLocked: Bool = false
    /// Post-unlock SkyLight teardown; cancelled if the screen locks again first.
    private var unlockTask: Task<Void, Never>?
    private var windowScreenDidChangeObserver: Any?
    private var previousScreens: [NSScreen]?

    init(camera: CameraModel) {
        // Migrate saved heights before the initial view model reads notch sizing.
        LegacyNonNotchHeightMigration.applyIfNeeded()
        primaryViewModel = BoringViewModel(camera: camera)
    }

    // MARK: - Public lookups (preserve AppDelegate's old API shape)

    var windows: [String: NSWindow] {
        contexts.compactMapValues { $0.window }
    }

    var viewModels: [String: BoringViewModel] {
        contexts.mapValues { $0.viewModel }
    }

    var window: NSWindow? { primaryWindow }

    // MARK: - Screen lock / unlock

    func screenLocked() {
        unlockTask?.cancel()
        unlockTask = nil
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    func screenUnlocked() {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
            setupDragDetectors()
        } else {
            leaveLockScreen()
        }
    }

    /// Every notch window this manager owns. Only one display mode's windows
    /// exist at a time (cleanupWindows(shouldInvert:) drops the other set).
    private var notchWindows: [BoringNotchSkyLightWindow] {
        ([primaryWindow] + contexts.values.map(\.window))
            .compactMap { $0 as? BoringNotchSkyLightWindow }
    }

    private func enableSkyLightOnAllWindows() {
        notchWindows.forEach { $0.enableSkyLight() }
    }

    /// Moves the windows off the lock screen, then replaces every window that
    /// was handed to SkyLight: undelegating leaves server-side state behind
    /// that makes the transparent margins swallow desktop clicks near the
    /// notch until the window is recreated. See docs/lock-screen.md.
    private func leaveLockScreen() {
        unlockTask?.cancel()
        unlockTask = Task { @MainActor [weak self] in
            // Delay disabling SkyLight to avoid flicker during unlock transition
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled, !self.isScreenLocked else { return }
            self.notchWindows.forEach { $0.disableSkyLight() }

            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !self.isScreenLocked else { return }
            self.replaceSkyLightDelegatedWindows()
            self.unlockTask = nil
        }
    }

    // MARK: - SkyLight window replacement
    //
    // Adapted from upstream PR #1346 (TemujinCalidius). The live NSHostingView
    // is moved to the new window rather than rebuilt: a fresh hosting view
    // shows a blank first frame and restarts the spectrum animation and the
    // album-art matched geometry. A snapshot of the old pixels sits under the
    // moved view while its layer re-hosts, so the notch is never blank.

    private func replaceSkyLightDelegatedWindows() {
        if let old = primaryWindow as? BoringNotchSkyLightWindow, old.wasDelegatedToSkyLight,
           let replacement = replaceWindow(old) {
            primaryWindow = replacement
        }
        for (uuid, context) in contexts {
            guard let old = context.window as? BoringNotchSkyLightWindow, old.wasDelegatedToSkyLight,
                  let replacement = replaceWindow(old) else { continue }
            contexts[uuid]?.window = replacement
        }
    }

    private func replaceWindow(_ old: BoringNotchSkyLightWindow) -> NSWindow? {
        guard !isScreenLocked, let liveView = old.contentView else { return nil }

        let snapshot = Self.snapshot(of: liveView)
        let window = makeNotchWindow()
        window.setFrame(old.frame, display: false)
        window.alphaValue = old.alphaValue

        let container = NotchPassthroughContainerView(frame: NSRect(origin: .zero, size: old.frame.size))
        container.autoresizesSubviews = true
        snapshot.frame = container.bounds
        container.addSubview(snapshot)
        window.contentView = container

        // Show the frozen snapshot above the old window before touching the live view.
        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        window.displayIfNeeded()
        CATransaction.flush()

        // Move the live view straight across (never window-less) and stack
        // it above the snapshot. The old window goes blank behind the snapshot.
        liveView.frame = container.bounds
        liveView.autoresizingMask = [.width, .height]
        container.addSubview(liveView, positioned: .above, relativeTo: snapshot)
        liveView.layoutSubtreeIfNeeded()
        CATransaction.flush()

        observeScreenChanges(of: window)

        // One run-loop turn later the live view has drawn: retire the old
        // window and drop the snapshot together.
        DispatchQueue.main.async {
            old.orderOut(nil)
            NotchSpaceManager.shared.notchSpace.windows.remove(old)
            old.close()
            snapshot.removeFromSuperview()
        }
        return window
    }

    /// Static bitmap of the view's current pixels (in-process, so unaffected
    /// by `sharingType = .none`).
    private static func snapshot(of view: NSView) -> NSImageView {
        let bounds = view.bounds
        let imageView = NSImageView(frame: bounds)
        imageView.imageScaling = .scaleNone
        imageView.autoresizingMask = [.width, .height]
        if bounds.width > 0, bounds.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            view.cacheDisplay(in: bounds, to: rep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(rep)
            imageView.image = image
        }
        return imageView
    }

    // MARK: - Window lifecycle

    func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? Defaults[.displayMode] != .allDisplays : Defaults[.displayMode] == .allDisplays

        if shouldCleanupMulti {
            for (uuid, context) in contexts {
                context.window?.close()
                if let window = context.window {
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                context.dragDetector?.stopMonitoring()
                contexts.removeValue(forKey: uuid)
            }
        } else {
            primaryDragDetector?.stopMonitoring()
            primaryDragDetector = nil
            if let window = primaryWindow {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            primaryWindow = nil
        }

        // ensure OSD integration reflects the current window state
        BoringViewCoordinator.shared.applyOSDSources()
    }

    /// A notch window with no content, on or off the lock screen to match the
    /// current lock state.
    private func makeNotchWindow() -> BoringNotchSkyLightWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }
        return window
    }

    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        let window = makeNotchWindow()

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        observeScreenChanges(of: window)
        return window
    }

    private func observeScreenChanges(of window: NSWindow) {
        // Observe when the window's screen changes so we can update drag detectors.
        // Remove any previous observer first — recreating windows used to
        // overwrite the token and leak the earlier observer each cycle.
        if let obs = windowScreenDidChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func adjustWindowPosition(changeAlpha: Bool = false) {
        let coordinator = BoringViewCoordinator.shared
        if Defaults[.displayMode] == .allDisplays {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in contexts.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = contexts[uuid]?.window {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                contexts[uuid]?.dragDetector?.stopMonitoring()
                contexts.removeValue(forKey: uuid)
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }

                if contexts[uuid] == nil {
                    contexts[uuid] = ScreenContext(
                        viewModel: BoringViewModel(screenUUID: uuid, camera: primaryViewModel.camera),
                        window: nil,
                        dragDetector: nil
                    )
                }

                if contexts[uuid]?.window == nil {
                    let viewModel = contexts[uuid]!.viewModel
                    let window = createBoringNotchWindow(for: screen, with: viewModel)
                    contexts[uuid]?.window = window
                }

                if let window = contexts[uuid]?.window {
                    let viewModel = contexts[uuid]!.viewModel
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let displayMode = Defaults[.displayMode]
            let selectedScreen: NSScreen?

            switch displayMode {
            case .preferredDisplay:
                selectedScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "")
            case .fallbackIfPreferredUnavailable:
                selectedScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "")
                    ?? NSScreen.main
            case .activeDisplay:
                selectedScreen = NSScreen.main
            case .allDisplays:
                return
            }

            guard let selectedScreen, let selectedUUID = selectedScreen.displayUUID else {
                if let window = primaryWindow {
                    window.alphaValue = 0
                }
                return
            }

            coordinator.selectedScreenUUID = selectedUUID

            primaryViewModel.screenUUID = selectedScreen.displayUUID
            primaryViewModel.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if primaryWindow == nil {
                primaryWindow = createBoringNotchWindow(for: selectedScreen, with: primaryViewModel)
            }

            if let window = primaryWindow {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if primaryViewModel.notchState == .closed {
                    primaryViewModel.close()
                }
            }
        }

        // windows might have been added/removed during the earlier logic –
        // update the OSD subsystems accordingly.
        coordinator.applyOSDSources()
    }

    func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                // Sync notch height with real value if mode is matchRealNotchSize
                syncNotchHeightIfNeeded()

                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    func noteInitialScreens() {
        previousScreens = NSScreen.screens
    }

    // MARK: - Drag detection

    func cleanupDragDetectors() {
        primaryDragDetector?.stopMonitoring()
        primaryDragDetector = nil
        for uuid in contexts.keys {
            contexts[uuid]?.dragDetector?.stopMonitoring()
            contexts[uuid]?.dragDetector = nil
        }
    }

    func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.displayMode] == .allDisplays {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = primaryWindow?.screen
                ?? NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        // Per-display detectors belong to windows created by adjustWindowPosition.
        guard Defaults[.displayMode] != .allDisplays || contexts[uuid]?.window != nil else { return }

        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width

        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        let detector = DragDetector(notchRegion: notchRegion)

        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }

        if Defaults[.displayMode] == .allDisplays {
            contexts[uuid]?.dragDetector = detector
        } else {
            primaryDragDetector = detector
        }
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard Defaults[.boringShelf] else { return }
        guard let uuid = screen.displayUUID else { return }

        let coordinator = BoringViewCoordinator.shared
        if Defaults[.displayMode] == .allDisplays, let viewModel = contexts[uuid]?.viewModel {
            if viewModel.open() {
                coordinator.currentView = .shelf
            }
        } else if Defaults[.displayMode] != .allDisplays, let windowScreen = primaryWindow?.screen, screen == windowScreen {
            if primaryViewModel.open() {
                coordinator.currentView = .shelf
            }
        }
    }

    // MARK: - Initial setup

    /// Creates the windows for the current configuration (previously inlined
    /// in applicationDidFinishLaunching).
    func prepareInitialWindows() {
        if Defaults[.displayMode] != .allDisplays {
            let viewModel = primaryViewModel
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                primaryWindow = createBoringNotchWindow(for: screen, with: viewModel)
            }
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()
        noteInitialScreens()
    }

    func togglePopover(_ sender: Any?) {
        if primaryWindow?.isVisible == true {
            primaryWindow?.orderOut(nil)
        } else {
            primaryWindow?.orderFrontRegardless()
        }
    }

    func cleanup() {
        cleanupDragDetectors()
        cleanupWindows()
    }
}

/// Content view for a replacement notch window. It never claims a click for
/// itself, so the transparent margins pass clicks through exactly as when the
/// hosting view is the window's content view.
private final class NotchPassthroughContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
