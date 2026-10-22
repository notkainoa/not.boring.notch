//
//  SessionLockState.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import CoreGraphics

/// UNDOCUMENTED API: `CGSessionCopyCurrentDictionary` is public, but the
/// `CGSSessionScreenIsLocked` key is not. Used to seed and re-check the lock
/// state, since the com.apple.screenIsLocked/Unlocked notifications only
/// report changes.
enum SessionLockState {
    /// nil when the session dictionary is unavailable.
    static var isScreenLocked: Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        // The key is absent while unlocked.
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
