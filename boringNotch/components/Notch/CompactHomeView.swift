//
//  CompactHomeView.swift
//  boringNotch
//
//  The home panel: the now-playing essentials (art, title, scrubber,
//  transport). Other features open as their own panels from the header
//  (see NotchPanel.swift).
//
//  Layout and proportions follow Atoll's MinimalisticMusicPlayerView
//  (https://github.com/Ebullioscopic/Atoll, GPL-3.0, itself a boring.notch
//  fork): 50pt album art, 12/10pt title and artist, a fixed-width
//  visualizer block on the right sized to match the trailing time label so
//  the bars centre over it, a progress row, and a transport row.
//
//  Transport and slider come from MusicPlayerControls.swift
//  (MusicControlSlotButton / MusicSliderView), so seeking and the buttons
//  behave the same wherever they're used.
//

import Defaults
import SwiftUI

struct CompactHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.showRemainingTime) private var showRemainingTime
    @Default(.showMediaSourceAppIcon) private var showMediaSourceAppIcon

    private let albumArtWidth: CGFloat = 45
    private let headerSpacing: CGFloat = 10
    /// Matches the trailing time label's width in the row below, so the
    /// visualizer's bars sit centred over "-0:00" rather than drifting.
    private let vizBlockWidth: CGFloat = 42
    private let vizBarWidth: CGFloat = 24

    // No idle branch, deliberately: it renders whatever MusicManager last
    // cached, so a paused or stopped track keeps its art, title and scrub
    // position. A "Nothing Playing" placeholder lost that state.
    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: albumArtWidth)

            progressRow
                .padding(.top, 6)

            transport
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        // Atoll's 15/3 formula assumes the player is the whole panel; here
        // the panel header sits above it, so these are trimmed to
        // land the panel at the intended overall height. The 2pt bottom pad
        // keeps the play/pause's hover fill from kissing the rounded corner
        // without adding a visible band of empty space.
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Header

    private var header: some View {
        GeometryReader { geo in
            let textWidth = max(
                0,
                geo.size.width - albumArtWidth - headerSpacing - (vizBlockWidth + headerSpacing)
            )

            HStack(alignment: .center, spacing: headerSpacing) {
                compactAlbumArt

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        musicManager.songTitle,
                        font: .system(size: 12, weight: .semibold),
                        color: .white,
                        frameWidth: textWidth
                    )

                    Text(musicManager.artistName)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            playerColorTinting
                                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                : .gray
                        )
                        .lineLimit(1)
                }
                .frame(width: textWidth, alignment: .leading)

                ZStack {
                    MusicVisualizer(
                        isPlaying: musicManager.isPlaying,
                        tintColor: coloredSpectrogram
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .gray
                    )
                    .frame(width: vizBarWidth, height: 16)
                }
                .frame(width: vizBlockWidth)
            }
        }
    }

    // MARK: - Progress

    private var progressRow: some View {
        MusicPlaybackTimeline(playbackRate: musicManager.playbackRate) { date in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                onValueChange: { MusicManager.shared.seek(to: $0) },
                trailingLabel: showRemainingTime ? .remaining : .duration
            )
            .padding(.top, 5)
            .frame(height: 36)
        }
        .onAppear { sliderValue = musicManager.elapsedTime }
    }

    // MARK: - Transport

    /// The user's configured control slots, clamped to the supported range.
    private var displayedSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        return slotConfig
            .padded(to: sanitizedLimit, filler: .none)
            .prefix(sanitizedLimit)
            .map { $0 }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                MusicControlSlotButton(
                    slot: slot,
                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var compactAlbumArt: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable().scaledToFill()
                .frame(width: albumArtWidth, height: albumArtWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Badge scaled to this art: a larger fixed badge spills outside
            // the corner of 45pt art.
            if showMediaSourceAppIcon && !musicManager.usingAppIconForArtwork {
                appIcon(for: musicManager.bundleIdentifier ?? MediaAppBundleID.appleMusic)
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: albumArtWidth, height: albumArtWidth)
    }
}

/// Output device list for the media-output button.
/// Row treatment follows macOS's AirPlay output menu: rounded highlight on
/// hover, circular icon badge marking the active output, no checkmark.
struct AudioOutputPicker: View {
    @ObservedObject var routeManager: AudioRouteManager
    let onSelect: () -> Void

    /// Apple's rows use a softly rounded rectangle, not a full pill.
    private let rowCornerRadius: CGFloat = 8
    private let listInset: CGFloat = 8
    private let badgeSize: CGFloat = 24
    private let hoverFill: CGFloat = 0.1
    private let pressedFill: CGFloat = 0.18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Output")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if routeManager.devices.isEmpty {
                // Enumeration is async, so an empty list on first open is
                // normal rather than an error worth alarming anyone about.
                Text("Looking for devices…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                ForEach(routeManager.devices) { device in
                    deviceRow(device)
                }
                .padding(.horizontal, listInset)
                .padding(.bottom, 6)
            }
        }
        .frame(minWidth: 220)
    }

    private func deviceRow(_ device: AudioOutputDevice) -> some View {
        let isSelected = device.id == routeManager.activeDeviceID

        return Button {
            routeManager.select(device)
            onSelect()
        } label: {
            HStack(spacing: 10) {
                deviceIcon(device, isSelected: isSelected)

                Text(device.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius))
        }
        .buttonStyle(AudioOutputRowButtonStyle(
            cornerRadius: rowCornerRadius,
            hoverFill: hoverFill,
            pressedFill: pressedFill
        ))
    }

    /// White badge + accent glyph for the active output, dim badge + white
    /// glyph for the rest.
    @ViewBuilder
    private func deviceIcon(_ device: AudioOutputDevice, isSelected: Bool) -> some View {
        Image(systemName: device.iconName)
            .font(.system(size: badgeSize * 0.55, weight: .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.white)
            .frame(width: badgeSize, height: badgeSize)
            .background(isSelected ? Color.white : Color.white.opacity(0.22), in: Circle())
    }
}

private struct AudioOutputRowButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    let hoverFill: CGFloat
    let pressedFill: CGFloat

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: CGFloat
        if configuration.isPressed {
            fill = pressedFill
        } else {
            fill = isHovering ? hoverFill : 0
        }

        return configuration.label
            .background(Color.white.opacity(fill), in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}
