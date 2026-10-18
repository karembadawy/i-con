import CoreGraphics
import Foundation

/// One app's status items. macOS 27 hides and shows items per app, so the app is the unit.
nonisolated struct MenuBarItem: Identifiable, Hashable, Sendable {
    let bundleID: String
    let pid: pid_t
    let name: String
    let bundlePath: String
    /// Frames of the app's status items, in global screen coordinates (top-left origin).
    /// Stale while the app is hidden.
    let frames: [CGRect]

    var id: String { bundleID }

    var frame: CGRect {
        frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }
    }
}

/// A running app that may own status items.
nonisolated struct RunningApp: Sendable {
    let bundleID: String
    let pid: pid_t
    let name: String
    let bundlePath: String
}
