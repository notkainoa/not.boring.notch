//
//  RaycastPanels.swift
//  boringNotch
//
//  PROTOTYPE: the expanded panels the home bar opens. The "⋯" Raycast
//  panel, the argument form for commands that take input, and stand-ins
//  for the calendar, mirror and shelf panels. Rows reuse the output
//  picker's AudioOutputRowButtonStyle and badge treatment, and the type
//  sizes match the notification view, so the panels look like the rest of
//  the notch.
//

import SwiftUI

/// Back button, glyph and title along the top of every panel.
struct HomePanelHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 4) {
            HoverButton(icon: "chevron.left", action: onBack)
                .accessibilityLabel("Back")

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing()
        }
        .frame(height: 30)
    }
}

extension HomePanelHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}

/// Section label, same as the output picker's "Output".
private func panelSectionLabel(_ text: LocalizedStringKey) -> some View {
    Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 2)
}

/// The output picker's circular badge, tinted per extension. Real commands
/// show the extension's PNG icon here.
struct RaycastCommandBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.12), in: Circle())
    }
}

// MARK: - "⋯" Raycast panel

struct RaycastPanelView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var store = RaycastPreviewStore.shared
    @Binding var panel: HomePanel?
    let onBack: () -> Void

    @State private var sentID: String?

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomePanelHeader(title: "Raycast", onBack: onBack) {
                HoverButton(icon: "gearshape") {
                    DispatchQueue.main.async {
                        SettingsWindowController.shared.showWindow()
                    }
                }
                .help("Raycast Settings")
                .accessibilityLabel("Raycast Settings")
            }

            panelSectionLabel("Pinned")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                ForEach(store.pinned.prefix(6)) { command in
                    commandRow(command)
                }
            }

            // Content pushed by the companion Raycast extension. Hidden
            // when nothing has been pushed.
            panelSectionLabel("GitHub · Review requests")
                .padding(.top, 4)

            ForEach(RaycastPushedItemPreview.samples) { item in
                pushedRow(item)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func commandRow(_ command: RaycastCommandPreview) -> some View {
        Button {
            run(command)
        } label: {
            HStack(spacing: 8) {
                RaycastCommandBadge(
                    symbol: sentID == command.id ? "checkmark" : command.symbol,
                    tint: sentID == command.id ? .green : command.tint
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Text(command.extensionTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: command.modeSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(AudioOutputRowButtonStyle(cornerRadius: 8, hoverFill: 0.1, pressedFill: 0.18))
        .help(Text(command.modeDescription))
    }

    private func pushedRow(_ item: RaycastPushedItemPreview) -> some View {
        Button {} label: {
            HStack(spacing: 8) {
                RaycastCommandBadge(symbol: item.symbol, tint: .white)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(AudioOutputRowButtonStyle(cornerRadius: 8, hoverFill: 0.1, pressedFill: 0.18))
    }

    private func run(_ command: RaycastCommandPreview) {
        switch command.mode {
        case .noView:
            sentID = command.id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                if sentID == command.id { sentID = nil }
            }
        case .arguments:
            panel = .arguments(command)
        case .view:
            vm.close()
        }
    }
}

// MARK: - Argument form

/// The form for commands with `arguments`. The fields come from the
/// manifest. The prototype shows them prefilled because it has no text input
/// yet; the real one uses the window's wantsKeyForTextInput.
struct RaycastArgumentFormView: View {
    let command: RaycastCommandPreview
    let onBack: () -> Void
    let onDone: () -> Void

    @State private var sent = false

    private var arguments: [RaycastCommandPreview.Argument] {
        if case .arguments(let arguments) = command.mode { return arguments }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomePanelHeader(
                title: LocalizedStringKey(command.title),
                subtitle: LocalizedStringKey(command.extensionTitle),
                onBack: onBack
            )

            ForEach(arguments, id: \.placeholder) { argument in
                HStack(spacing: 8) {
                    RaycastCommandBadge(symbol: command.symbol, tint: command.tint)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(argument.placeholder)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(argument.sampleValue)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button(action: run) {
                    HStack(spacing: 5) {
                        Text(sent ? "Sent" : "Run")
                        Image(systemName: sent ? "checkmark" : "return")
                            .contentTransition(.symbolEffect)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(sent ? Color.green.opacity(0.35) : .white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func run() {
        sent = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            onDone()
        }
    }
}

// MARK: - Built-in panel stand-ins

/// Stands in for the item 2 panels, at their declared sizes, so the shape
/// morph and the sizes can be judged before the real views move in.
struct FeaturePlaceholderPanel: View {
    let feature: HomeFeature
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HomePanelHeader(title: feature.title, onBack: onBack)

            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 18))
                        Text("Panel placeholder")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(height: feature.panelSize.height - 34)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}
