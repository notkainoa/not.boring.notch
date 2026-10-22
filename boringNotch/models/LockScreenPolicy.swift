//
//  LockScreenPolicy.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  What the notch may show while the screen is locked. Only matters when
//  "Show notch on lock screen" is on; otherwise there is no notch while
//  locked. See docs/lock-screen.md.
//

import Defaults

/// A notch feature with its own lock-screen visibility.
enum LockScreenFeature: String, CaseIterable, Identifiable {
    case music
    case battery
    case notifications
    case calendar
    case shelf
    case mirror

    var id: String { rawValue }

    /// The setting for this feature, ready for `@Default(feature.visibilityKey)`.
    var visibilityKey: Defaults.Key<LockScreenVisibility> {
        switch self {
        case .music: .lockScreenMusicVisibility
        case .battery: .lockScreenBatteryVisibility
        case .notifications: .lockScreenNotificationsVisibility
        case .calendar: .lockScreenCalendarVisibility
        case .shelf: .lockScreenShelfVisibility
        case .mirror: .lockScreenMirrorVisibility
        }
    }

    var visibility: LockScreenVisibility { Defaults[visibilityKey] }

    /// The feature a closed-notch alert belongs to, if it is policy-controlled.
    /// OSDs (volume, brightness, mic) aren't private and always show.
    init?(_ type: SneakContentType) {
        switch type {
        case .music: self = .music
        case .battery: self = .battery
        default: return nil
        }
    }
}

/// How a feature appears while locked. Room for a `redacted` case (calendar
/// times without titles, shelf counts without names) without a migration.
enum LockScreenVisibility: String, CaseIterable, Defaults.Serializable {
    case visible
    case hidden
}
