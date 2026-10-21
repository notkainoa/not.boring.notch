//
//  RaycastSettingsView.swift
//  boringNotch
//
//  PROTOTYPE: Settings → Raycast with placeholder commands. Pinning and
//  ordering here update the notch's home bar live through
//  RaycastPreviewStore, but nothing is saved and nothing talks to Raycast.
//

import SwiftUI

struct RaycastSettingsView: View {
    @ObservedObject private var store = RaycastPreviewStore.shared
    @State private var search = ""

    private var filtered: [RaycastCommandPreview] {
        guard !search.isEmpty else { return RaycastCommandPreview.installed }
        return RaycastCommandPreview.installed.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.extensionTitle.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "hammer")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview with placeholder commands")
                            .font(.headline)
                        Text("These aren't read from Raycast yet, and changes aren't saved.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section {
                barPreview

                Stepper(value: $store.visiblePinCount, in: RaycastPreviewStore.visiblePinRange) {
                    Text("Commands shown in the bar: \(store.visiblePinCount)")
                }

                ForEach(Array(store.pinned.enumerated()), id: \.element.id) { index, command in
                    pinnedRow(command, index: index)
                }
            } header: {
                Text("Pinned")
            } footer: {
                HelpText("The rest of your pinned commands are in the Raycast panel, opened from \"⋯\" in the bar.")
            }

            Section {
                TextField("Search commands", text: $search)

                ForEach(filtered) { command in
                    installedRow(command)
                }
            } header: {
                Text("Installed commands")
            } footer: {
                HelpText("Raycast asks once per command before the notch can run it. Use Try it to answer that prompt now.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Raycast")
    }

    /// The bar as it looks in the notch, like the media slot preview.
    private var barPreview: some View {
        HStack(spacing: 6) {
            ForEach(HomeFeature.allCases) { feature in
                Image(systemName: feature.symbol)
                    .frame(width: 24, height: 24)
            }
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: 16)
            ForEach(store.pinned.prefix(store.visiblePinCount)) { command in
                Image(systemName: command.symbol)
                    .foregroundStyle(command.tint)
                    .frame(width: 24, height: 24)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 24)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
    }

    private func pinnedRow(_ command: RaycastCommandPreview, index: Int) -> some View {
        HStack(spacing: 10) {
            commandLabel(command)

            if index >= store.visiblePinCount {
                customBadge(text: "In ⋯ panel")
            }

            Button {
                withAnimation { store.move(command, by: -1) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                withAnimation { store.move(command, by: 1) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == store.pinned.count - 1)

            Button {
                withAnimation { store.setPinned(false, command) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Unpin")
        }
    }

    private func installedRow(_ command: RaycastCommandPreview) -> some View {
        HStack(spacing: 10) {
            commandLabel(command)

            Button("Try it") {}
                .disabled(true)
                .help("Runs the command once so Raycast's confirmation appears now")

            Toggle("Pinned", isOn: Binding(
                get: { store.isPinned(command) },
                set: { pinned in withAnimation { store.setPinned(pinned, command) } }
            ))
            .labelsHidden()
        }
    }

    private func commandLabel(_ command: RaycastCommandPreview) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .foregroundStyle(command.tint)
                .frame(width: 22, height: 22)
                .background(Color(nsColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                Text("\(command.extensionTitle) · \(Text(command.modeDescription))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
