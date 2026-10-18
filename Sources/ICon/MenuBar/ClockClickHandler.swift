import AppKit
import OSLog

/// macOS's exam restriction, which i-con uses to hide icons, also blocks Notification Center, so
/// clicking the clock does nothing while anything is hidden. This lifts the restriction for a
/// click on the clock, replays the click, and restores the restriction once Notification Center
/// closes. Hidden icons show in the menu bar while Notification Center is open.
final class ClockClickHandler {
    weak var state: AppState?

    private var monitor: Any?
    private var session: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.karembadawy.icon", category: "clock")

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp(at: MenuBarGeometry.topLeft(NSEvent.mouseLocation)) }
        }
    }

    private func mouseUp(at point: CGPoint) {
        // The replayed click lands here too; `session` keeps it from starting another round.
        guard session == nil, let state, state.engineState == .active, state.isClock(at: point) else { return }
        session = Task {
            await openNotificationCenter(clickingAt: point, state: state)
            session = nil
        }
    }

    private func openNotificationCenter(clickingAt point: CGPoint, state: AppState) async {
        logger.info("Clock clicked; lifting the restriction for Notification Center")
        await state.setHidingSuspended(true)

        var opened = false
        for _ in 0..<2 where !opened {
            // Give macOS a moment to drop the restriction before replaying the click.
            try? await Task.sleep(for: .milliseconds(250))
            Self.click(at: point)
            for _ in 0..<10 where !opened {
                try? await Task.sleep(for: .milliseconds(150))
                opened = Self.isNotificationCenterOpen()
            }
        }
        if opened {
            while Self.isNotificationCenterOpen() {
                try? await Task.sleep(for: .milliseconds(300))
            }
        } else {
            logger.error("Notification Center didn't open")
        }
        await state.setHidingSuspended(false)
    }

    /// Its panel sits above normal windows; its desktop widgets sit below the desktop.
    private static func isNotificationCenterOpen() -> Bool {
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.apple.notificationcenterui" }
            .map(\.processIdentifier))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            pids.contains(window[kCGWindowOwnerPID as String] as? pid_t ?? -1) && (window[kCGWindowLayer as String] as? Int ?? 0) > 0
        }
    }

    /// The pointer is already on the clock (the user just clicked it), so nothing visibly moves.
    private static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
}
