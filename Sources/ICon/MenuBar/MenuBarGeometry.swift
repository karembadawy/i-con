import AppKit

/// Screen geometry helpers. AX and CGWindow use global coordinates with a top-left origin;
/// AppKit uses a bottom-left origin.
enum MenuBarGeometry {
    /// Converts an AppKit screen point to global top-left coordinates.
    static func topLeft(_ point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Whether an item is drawn where it can be captured: inside a menu bar, not behind the
    /// notch, and not overlapping anything in `obstacles` (other items' frames; macOS 27 stacks
    /// overflowed items on its chevron).
    static func isCapturable(_ frame: CGRect, obstacles: [CGRect]) -> Bool {
        guard frame.width > 0, frame.height > 0, let primary = NSScreen.screens.first else { return false }
        for screen in NSScreen.screens {
            let bar = CGRect(
                x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                width: screen.frame.width, height: max(screen.safeAreaInsets.top, 40)
            )
            guard bar.contains(frame) else { continue }
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let notch = CGRect(
                    x: screen.frame.minX + left.width, y: bar.minY,
                    width: screen.frame.width - left.width - right.width, height: bar.height
                )
                if notch.intersects(frame) { return false }
            }
            return !obstacles.contains { $0.intersects(frame.insetBy(dx: 2, dy: 2)) }
        }
        return false
    }

    /// The process that owns the frontmost window under an AppKit screen point.
    static func ownerPID(at point: NSPoint) -> pid_t? {
        let location = topLeft(point)
        for window in onScreenWindows() {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.contains(location),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    /// Whether the app shows a menu or popover: a window above the normal level that sits below
    /// the menu bar (its status item itself lives in the menu bar).
    static func hasOpenMenu(pid: pid_t) -> Bool {
        onScreenWindows().contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  (window[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return rect.minY > 20
        }
    }

    /// Front to back.
    private static func onScreenWindows() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }
}
