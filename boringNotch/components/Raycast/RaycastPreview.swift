//
//  RaycastPreview.swift
//  boringNotch
//
//  PROTOTYPE: placeholder Raycast data for judging the home bar and panels
//  visually (docs/raycast-integration.md, "Product design"). Nothing here
//  talks to Raycast. The real version reads commands from
//  ~/.config/raycast/extensions/*/package.json and launches them by
//  raycast:// deeplink. Until then these entries are modelled on real
//  extensions (most are installed on the dev machine), so the layout is
//  judged against realistic titles.
//

import SwiftUI

struct RaycastCommandPreview: Identifiable, Equatable {
    /// How a click behaves, from the manifest's `mode` and `arguments`.
    enum Mode: Equatable {
        /// `no-view`: runs in the background, the notch shows "sent".
        case noView
        /// `view`: the notch collapses and Raycast opens.
        case view
        /// Has `arguments`: the notch expands into a small form first.
        case arguments([Argument])
    }

    struct Argument: Equatable {
        let placeholder: String
        /// Prefilled so the form reads as filled in; the prototype has no
        /// text input yet.
        let sampleValue: String
    }

    let id: String
    let title: String
    let extensionTitle: String
    /// Stands in for the extension's own PNG icon from `assets/`.
    let symbol: String
    let tint: Color
    let mode: Mode

    var modeDescription: LocalizedStringKey {
        switch mode {
        case .noView: "Runs in background"
        case .view: "Opens Raycast"
        case .arguments: "Asks for input"
        }
    }

    var modeSymbol: String {
        switch mode {
        case .noView: "return"
        case .view: "arrow.up.forward.app"
        case .arguments: "text.cursor"
        }
    }

    static let installed: [RaycastCommandPreview] = [
        .init(id: "pick-color", title: "Pick Color", extensionTitle: "Color Picker",
              symbol: "eyedropper", tint: .pink, mode: .noView),
        .init(id: "recognize-text", title: "Recognize Text", extensionTitle: "ScreenOCR",
              symbol: "text.viewfinder", tint: .teal, mode: .noView),
        .init(id: "convert-color", title: "Convert Color", extensionTitle: "Color Picker",
              symbol: "paintpalette", tint: .orange,
              mode: .arguments([.init(placeholder: "Color", sampleValue: "#FF6363")])),
        .init(id: "clipboard-history", title: "Clipboard History", extensionTitle: "Raycast",
              symbol: "doc.on.clipboard", tint: .red, mode: .view),
        .init(id: "search-icons", title: "Search Icons", extensionTitle: "Lucide Icons Search",
              symbol: "magnifyingglass", tint: .mint, mode: .view),
        .init(id: "start-timer", title: "Start Timer", extensionTitle: "Timers",
              symbol: "timer", tint: .yellow,
              mode: .arguments([.init(placeholder: "Duration", sampleValue: "25m")])),
        .init(id: "detect-barcode", title: "Detect Barcode/QR Code", extensionTitle: "ScreenOCR",
              symbol: "qrcode.viewfinder", tint: .teal, mode: .noView),
        .init(id: "browse-hugeicons", title: "Browse Hugeicons", extensionTitle: "Hugeicons UI",
              symbol: "square.grid.2x2", tint: .blue, mode: .view),
        .init(id: "my-schedule", title: "My Schedule", extensionTitle: "Calendar",
              symbol: "calendar", tint: .red, mode: .view),
    ]
}

/// One row of content pushed by the companion Raycast extension into the
/// "⋯" panel. Placeholder only.
struct RaycastPushedItemPreview: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String

    static let samples: [RaycastPushedItemPreview] = [
        .init(title: "Fix compact hit-testing", subtitle: "not.boring.notch #12 · review requested",
              symbol: "arrow.triangle.pull"),
        .init(title: "Bluetooth live activity", subtitle: "not.boring.notch #9 · checks passing",
              symbol: "checkmark.circle"),
    ]
}

/// Shared between the notch and Settings so pinning in Settings updates the
/// bar live. Not persisted: the real version stores pins under a `Defaults`
/// key, like `musicControlSlots`.
@MainActor
final class RaycastPreviewStore: ObservableObject {
    static let shared = RaycastPreviewStore()

    @Published var pinnedIDs: [String] = [
        "pick-color", "convert-color", "clipboard-history", "recognize-text",
        "start-timer", "search-icons",
    ]
    /// How many pins sit in the bar; the rest live in the "⋯" panel.
    @Published var visiblePinCount: Int = 4

    static let visiblePinRange = 2...5

    var pinned: [RaycastCommandPreview] {
        pinnedIDs.compactMap { id in RaycastCommandPreview.installed.first { $0.id == id } }
    }

    func isPinned(_ command: RaycastCommandPreview) -> Bool {
        pinnedIDs.contains(command.id)
    }

    func setPinned(_ pinned: Bool, _ command: RaycastCommandPreview) {
        if pinned {
            guard !isPinned(command) else { return }
            pinnedIDs.append(command.id)
        } else {
            pinnedIDs.removeAll { $0 == command.id }
        }
    }

    func move(_ command: RaycastCommandPreview, by offset: Int) {
        guard let index = pinnedIDs.firstIndex(of: command.id) else { return }
        let target = index + offset
        guard pinnedIDs.indices.contains(target) else { return }
        pinnedIDs.swapAt(index, target)
    }
}
