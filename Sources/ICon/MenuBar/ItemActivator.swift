import AppKit
import OSLog

/// Opens a hidden item from the popup. macOS 27 attaches an item's menu to its real menu bar
/// icon, so the app is shown in the menu bar for as long as its menu is open, then hidden again.
final class ItemActivator {
    weak var state: AppState?

    private var revealedPID: pid_t?
    private var monitor: Any?
    private var watcher: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.karembadawy.icon", category: "activator")

    func activate(_ item: MenuBarItem) {
        guard let state else { return }
        endReveal()
        revealedPID = item.pid

        Task {
            await state.setRevealed(item.bundleID)
            // Give the menu bar a moment to lay the item out.
            try? await Task.sleep(for: .milliseconds(250))
            guard revealedPID == item.pid else { return }
            if !state.icons.hasCapture(item.bundleID) {
                await state.captureIcons(for: [item.bundleID], waitForLayout: false)
            }

            let pid = item.pid
            let pressed = await Task.detached { AXInventory.pressOnlyItem(pid: pid) }.value
            if pressed {
                logger.info("Opened \(item.bundleID, privacy: .public)")
            } else {
                let frames = await Task.detached { AXInventory.frames(pid: pid) }.value
                if frames.count == 1, let frame = frames.first {
                    Self.click(at: CGPoint(x: frame.midX, y: frame.midY))
                    logger.info("Clicked \(item.bundleID, privacy: .public) at \(frame.midX), \(frame.midY)")
                } else {
                    logger.info("Showing \(item.bundleID, privacy: .public): \(frames.count) items, user picks")
                }
            }
            watch(pid: pid)
        }
    }

    /// Hides the revealed app again.
    func endReveal() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        watcher?.cancel()
        watcher = nil
        guard revealedPID != nil else { return }
        revealedPID = nil
        logger.info("Hiding the revealed app again")
        Task { await state?.setRevealed(nil) }
    }

    /// Hides the app again once its menu closes, on a click elsewhere, or after a minute.
    private func watch(pid: pid_t) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let pid = self.revealedPID else { return }
                // Clicks inside the app's own menus and popovers keep it shown.
                if MenuBarGeometry.ownerPID(at: NSEvent.mouseLocation) != pid {
                    self.endReveal()
                }
            }
        }
        watcher = Task { [weak self] in
            var sawMenu = false
            for _ in 0..<240 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                if MenuBarGeometry.hasOpenMenu(pid: pid) {
                    sawMenu = true
                } else if sawMenu {
                    break
                }
            }
            guard !Task.isCancelled else { return }
            self?.endReveal()
        }
    }

    /// Fallback when AXPress isn't supported: a real click, then the cursor goes back.
    private static func click(at point: CGPoint) {
        let original = MenuBarGeometry.topLeft(NSEvent.mouseLocation)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(original)
    }
}
