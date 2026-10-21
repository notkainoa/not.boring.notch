//
//  NotchPanelHeader.swift
//  boringNotch
//
//  The open notch's top row: feature panel buttons on the leading side,
//  battery and settings (or the open-notch OSD) on the trailing side. On a
//  notched display the two sides sit either side of the camera cutout. On
//  a display without a notch it's one bar with no gap in the middle.
//

import Defaults
import SwiftUI

struct NotchPanelHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    let panels: [NotchPanel]
    let activePanel: NotchPanelID
    /// Width of the physical cutout to leave empty, 0 without a notch.
    let cutoutWidth: CGFloat
    let onSelect: (NotchPanelID) -> Void

    @Default(.settingsIconInNotch) private var settingsIconInNotch
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showOpenNotchOSD) private var showOpenNotchOSD

    static let buttonSize: CGFloat = 24
    static let buttonSpacing: CGFloat = 4
    static let minimumHeight: CGFloat = 28
    /// Room each side needs beside the cutout: three panel buttons on the
    /// leading side, or battery and gear on the trailing side.
    static let sideWidth: CGFloat = 88
    /// How far the header may reach into the shape's side padding. That
    /// padding is sized for the flared top corners, which at header height
    /// have already curved most of the way in.
    static let edgeOverhang: CGFloat = 8

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Self.buttonSpacing) {
                ForEach(panels) { panel in
                    NotchPanelButton(
                        panel: panel,
                        isActive: panel.id == activePanel,
                        action: { onSelect(panel.id) }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if cutoutWidth > 0 {
                Color.clear.frame(width: cutoutWidth)
            }

            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.gray)
    }

    @ViewBuilder
    private var trailing: some View {
        let sneakPeek = coordinator.sneakPeekState(for: vm.screenUUID)
        if showOpenNotchOSD, isOSDType(sneakPeek.type), coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
            OpenNotchOSD(
                type: coordinator.binding(for: vm.screenUUID).type,
                value: coordinator.binding(for: vm.screenUUID).value,
                icon: coordinator.binding(for: vm.screenUUID).icon,
                accent: coordinator.binding(for: vm.screenUUID).accent
            )
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            HStack(spacing: Self.buttonSpacing) {
                if settingsIconInNotch {
                    Button {
                        DispatchQueue.main.async {
                            SettingsWindowController.shared.showWindow()
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: Self.buttonSize, height: Self.buttonSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(Text("Settings"))
                }
                if showBatteryIndicator {
                    BoringBatteryView(
                        batteryWidth: 24,
                        isCharging: batteryModel.isCharging,
                        isInLowPowerMode: batteryModel.isInLowPowerMode,
                        isPluggedIn: batteryModel.isPluggedIn,
                        levelBattery: batteryModel.levelBattery,
                        maxCapacity: batteryModel.maxCapacity,
                        timeToFullCharge: batteryModel.timeToFullCharge,
                        timeToDischarge: batteryModel.timeToDischarge,
                        maxAdapterWatts: batteryModel.maxAdapterWatts,
                        isForNotification: false
                    )
                }
            }
        }
    }

    private func isOSDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

private struct NotchPanelButton: View {
    let panel: NotchPanel
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: panel.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive || isHovering ? .white : .gray)
                .frame(width: NotchPanelHeader.buttonSize, height: NotchPanelHeader.buttonSize)
                .background(
                    Circle().fill(.white.opacity(isActive ? 0.18 : (isHovering ? 0.08 : 0)))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(panel.title))
        .accessibilityLabel(Text(panel.title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}
