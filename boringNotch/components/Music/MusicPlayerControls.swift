//
//  MusicPlayerControls.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

/// A single transport button: sizing, glyphs and the swipe-to-skip bounce.
struct MusicControlSlotButton: View {
    @ObservedObject var musicManager = MusicManager.shared
    let slot: MusicControlButton
    let horizontalMediaGestureFeedback: CGFloat

    var body: some View {
        Group {
            switch slot {
            case .shuffle:
                HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                    MusicManager.shared.toggleShuffle()
                }
            case .previous:
                HoverButton(icon: "backward.fill", scale: .medium) {
                    MusicManager.shared.previousTrack()
                }
                .scaleEffect(horizontalMediaGestureFeedback > 0 ? 1.12 : 1)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
            case .playPause:
                HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                    MusicManager.shared.togglePlay()
                }
            case .next:
                HoverButton(icon: "forward.fill", scale: .medium) {
                    MusicManager.shared.nextTrack()
                }
                .scaleEffect(horizontalMediaGestureFeedback < 0 ? 1.12 : 1)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
            case .repeatMode:
                HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                    MusicManager.shared.toggleRepeat()
                }
            case .mediaOutput:
                MediaOutputSlotButton()
            case .volume:
                VolumeControlView()
            case .favorite:
                FavoriteControlButton()
            case .goBackward:
                HoverButton(icon: "gobackward.15", scale: .medium) {
                    MusicManager.shared.skip(seconds: -15)
                }
            case .goForward:
                HoverButton(icon: "goforward.15", scale: .medium) {
                    MusicManager.shared.skip(seconds: 15)
                }
            case .none:
                Color.clear.frame(height: 1)
            }
        }
        .help(slot.actionLabel(isPlaying: musicManager.isPlaying, isFavorite: musicManager.isFavoriteTrack))
        .accessibilityLabel(slot.actionLabel(isPlaying: musicManager.isPlaying, isFavorite: musicManager.isFavoriteTrack))
        .accessibilityHidden(slot == .none)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct MusicPlaybackTimeline<Content: View>: View {
    let playbackRate: Double
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: playbackRate > 0 ? musicPlaybackTickInterval : nil)) { context in
            content(context.date)
        }
    }
}

private let musicPlaybackTickInterval: TimeInterval = 0.2

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

/// Audio-output slot for a control row. Shows where audio is going and
/// switches it, via a popover device picker. Both layouts use this through
/// MusicControlSlotButton.
struct MediaOutputSlotButton: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @State private var showingPicker = false
    @State private var isHoveringButton = false
    @State private var isHoveringPopover = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HoverButton(icon: routeSymbol, scale: .medium) {
            // Enumerate on open rather than polling: devices come and go
            // (AirPods connecting, a display waking) and a list built at
            // launch would be stale by the time anyone opened it.
            if routeManager.devices.isEmpty {
                // A popover sizes its window once, at presentation. Opening
                // on the empty placeholder would size it to that and
                // truncate names that arrive a moment later.
                routeManager.refreshDevices { showingPicker = true }
            } else {
                routeManager.refreshDevices()
                showingPicker.toggle()
            }
        }
        .onHover { hovering in
            isHoveringButton = hovering
            if hovering {
                hideTask?.cancel()
                hideTask = nil
            } else {
                scheduleHideIfNeeded()
            }
        }
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            AudioOutputPicker(routeManager: routeManager) {
                showingPicker = false
            }
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showingPicker) { _, isShowing in
            vm.isPopoverActive = isShowing
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
            vm.isPopoverActive = false
        }
    }

    /// Prefer the live device's own icon; fall back to the resolver's
    /// classification before the first enumeration has run.
    private var routeSymbol: String {
        routeManager.activeDevice?.iconName ?? AudioOutputRouteResolver.shared.outputRouteSymbol()
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showingPicker = false } }
        }
    }
}

// Internal so the compact layout's slot row can share the padding rule.
extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)
            .help(MusicControlButton.volume.label)
            .accessibilityLabel(MusicControlButton.volume.label)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .accessibilityLabel(MusicControlButton.volume.label)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }

    /// Level-reactive speaker waves (v2.7.3 behavior). The route-device
    /// glyphs (AirPods, headphones, …) that replaced these belong to the
    /// media-output button beside this slot — duplicating them here made
    /// volume and output indistinguishable and static while dragging.
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void

    // Ported from Atoll (GPL-3.0, itself a boring.notch fork) so the
    // trailing timestamp can count down instead of showing the duration.
    var trailingLabel: TrailingLabel = .duration

    enum TrailingLabel {
        case duration
        /// Counts down: "-2:56".
        case remaining
    }

    var body: some View {
        VStack {
            sliderCore
                .frame(height: sliderFrameHeight, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    private var sliderCore: some View {
        CustomSlider(
            value: $sliderValue,
            range: 0...duration,
            color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
            dragging: $dragging,
            lastDragged: $lastDragged,
            onValueChange: onValueChange
        )
    }

    private var timeLabelColor: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
    }

    private var trailingTimeText: String {
        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            return "-" + timeString(from: max(duration - sliderValue, 0))
        }
    }

    private var sliderFrameHeight: CGFloat {
        10
    }

    func timeString(from seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
