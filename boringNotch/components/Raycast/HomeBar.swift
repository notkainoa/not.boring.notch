//
//  HomeBar.swift
//  boringNotch
//
//  PROTOTYPE: the bar under now playing on the compact home, and the
//  container that swaps the player for an expanded panel (VISION items 2
//  and 6). Built-in feature buttons, then pinned Raycast commands, then
//  "⋯" for the Raycast panel. Every button is a HoverButton, the same
//  control the transport row uses, so the bar reads as part of the player
//  rather than a new widget.
//

import SwiftUI

/// Built-in features that get a panel. Placeholder panels for now; item 2
/// replaces them with the real calendar, mirror and shelf views.
enum HomeFeature: String, CaseIterable, Identifiable {
    case calendar
    case mirror
    case shelf

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .mirror: "web.camera"
        case .shelf: "tray"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .calendar: "Calendar"
        case .mirror: "Mirror"
        case .shelf: "Shelf"
        }
    }

    /// Each panel declares its own size (item 2). Mirror is 16:9 inside the
    /// compact width; calendar and shelf grow wider.
    var panelSize: CGSize {
        switch self {
        case .calendar: CGSize(width: 440, height: 150)
        case .mirror: CGSize(width: 336, height: 176)
        case .shelf: CGSize(width: 440, height: 96)
        }
    }
}

enum HomePanel: Equatable {
    case feature(HomeFeature)
    case raycast
    case arguments(RaycastCommandPreview)

    var width: CGFloat {
        switch self {
        case .feature(let feature): feature.panelSize.width
        case .raycast: 440
        case .arguments: 336
        }
    }
}

/// The open compact notch: player plus bar, or one expanded panel. The
/// width change is what morphs the notch shape, since the open compact
/// notch sizes to its content.
struct CompactHomeContainer: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool

    @State private var panel: HomePanel?

    /// The player's own width (Atoll's 420 less 20%), unchanged from when
    /// ContentView set it directly.
    static let homeWidth: CGFloat = 336

    var body: some View {
        Group {
            switch panel {
            case nil:
                VStack(spacing: 0) {
                    CompactHomeView(
                        albumArtNamespace: albumArtNamespace,
                        horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
                    )
                    .onHover { hovering in
                        isHoveringMusicArea = hovering
                    }
                    .onDisappear {
                        isHoveringMusicArea = false
                    }

                    HomeBarView(panel: $panel)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                }
            case .feature(let feature):
                FeaturePlaceholderPanel(feature: feature, onBack: back)
            case .raycast:
                RaycastPanelView(panel: $panel, onBack: back)
            case .arguments(let command):
                RaycastArgumentFormView(command: command, onBack: back, onDone: back)
            }
        }
        .transition(.opacity)
        .frame(width: panel?.width ?? Self.homeWidth)
        .animation(StandardAnimations.open, value: panel)
    }

    private func back() {
        panel = nil
    }
}

struct HomeBarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var store = RaycastPreviewStore.shared
    @Binding var panel: HomePanel?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HomeFeature.allCases) { feature in
                HoverButton(icon: feature.symbol) {
                    panel = .feature(feature)
                }
                .help(Text(feature.title))
                .accessibilityLabel(Text(feature.title))
            }

            separator

            ForEach(store.pinned.prefix(store.visiblePinCount)) { command in
                RaycastPinButton(command: command, panel: $panel)
            }

            Spacer(minLength: 0)

            HoverButton(icon: "ellipsis") {
                panel = .raycast
            }
            .help("Raycast")
            .accessibilityLabel("Raycast")
        }
        .frame(height: 32)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 6)
    }
}

/// A pinned command. Its click depends on the command's mode; Raycast never
/// reports back, so "sent" means the deeplink went out, not that the
/// command finished.
struct RaycastPinButton: View {
    @EnvironmentObject var vm: BoringViewModel
    let command: RaycastCommandPreview
    @Binding var panel: HomePanel?

    @State private var feedbackSymbol: String?

    var body: some View {
        HoverButton(
            icon: feedbackSymbol ?? command.symbol,
            iconColor: feedbackSymbol == nil ? command.tint : .green
        ) {
            run()
        }
        .help(Text("\(command.title) — \(command.extensionTitle)"))
        .accessibilityLabel(Text(command.title))
    }

    private func run() {
        switch command.mode {
        case .noView:
            flash("checkmark")
        case .arguments:
            panel = .arguments(command)
        case .view:
            // Collapse and hand over to Raycast. The prototype only collapses.
            flash("arrow.up.forward.app") {
                vm.close()
            }
        }
    }

    private func flash(_ symbol: String, then completion: (() -> Void)? = nil) {
        feedbackSymbol = symbol
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            feedbackSymbol = nil
            completion?()
        }
    }
}
