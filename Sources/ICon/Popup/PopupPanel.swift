import AppKit
import SwiftUI

/// A borderless panel under the chevron that doesn't activate the app (so the frontmost app
/// keeps focus). It sizes itself to the SwiftUI content and closes on outside clicks or Esc.
final class PopupPanel: NSPanel {
    var onDismiss: (() -> Void)?

    /// Top-center point the panel hangs from, in screen coordinates.
    private var anchor = NSPoint.zero
    private var monitors: [Any] = []

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = .preferredContentSize
        contentViewController = hosting

        NotificationCenter.default.addObserver(self, selector: #selector(didResize), name: NSWindow.didResizeNotification, object: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(below rect: NSRect) {
        anchor = NSPoint(x: rect.midX, y: rect.minY - 6)
        reposition()
        makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func dismiss() {
        guard isVisible else { return }
        removeMonitors()
        orderOut(nil)
        onDismiss?()
    }

    @objc private func didResize() {
        // Keep the top edge under the chevron as the content grows or shrinks.
        reposition()
    }

    private func reposition() {
        let size = frame.size
        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.x, y: anchor.y - 1)) }) ?? NSScreen.main {
            let bounds = screen.visibleFrame
            origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        }
        setFrameOrigin(origin)
    }

    private func installMonitors() {
        removeMonitors()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            self?.dismiss()
            return nil
        }) {
            monitors.append(monitor)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
