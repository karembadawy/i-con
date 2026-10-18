import AppKit
import ApplicationServices
import os

/// Finds other apps' status items through Accessibility (each app's `AXExtrasMenuBar`).
enum AXInventory {
    /// Owns the system items (clock, Control Center, …) and macOS 27's overflow chevron. They stay
    /// under macOS control, but their frames matter: overflowed items are stacked on the chevron.
    nonisolated static let systemBundleID = "com.apple.MenuBarAgent"

    static func runningApps() -> [RunningApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier,
                  let bundleURL = app.bundleURL, bundleURL.pathExtension == "app"
            else { return nil }
            return RunningApp(bundleID: bundleID, pid: app.processIdentifier, name: app.localizedName ?? bundleID, bundlePath: bundleURL.path)
        }
    }

    /// Scans every app in parallel, off the main thread. Unresponsive apps time out after 0.1s.
    nonisolated static func scan(_ apps: [RunningApp]) async -> [MenuBarItem] {
        await Task.detached(priority: .userInitiated) {
            let found = OSAllocatedUnfairLock(initialState: [String: MenuBarItem]())
            DispatchQueue.concurrentPerform(iterations: apps.count) { index in
                let app = apps[index]
                let frames = statusItems(pid: app.pid).compactMap(frame(of:))
                guard !frames.isEmpty else { return }
                found.withLock { items in
                    let existing = items[app.bundleID]?.frames ?? []
                    items[app.bundleID] = MenuBarItem(bundleID: app.bundleID, pid: app.pid, name: app.name, bundlePath: app.bundlePath, frames: existing + frames)
                }
            }
            return found.withLock { Array($0.values) }
        }.value
    }

    /// Current frames of one app's status items.
    nonisolated static func frames(pid: pid_t) -> [CGRect] {
        statusItems(pid: pid).compactMap(frame(of:))
    }

    /// Presses the app's status item when it has exactly one (with several, the user picks).
    nonisolated static func pressOnlyItem(pid: pid_t) -> Bool {
        let items = statusItems(pid: pid)
        guard items.count == 1 else { return false }
        AXUIElementSetMessagingTimeout(items[0], 0.25)
        // An open menu keeps the app busy until it closes, so a timeout still means it was pressed.
        let result = AXUIElementPerformAction(items[0], kAXPressAction as CFString)
        return result == .success || result == .cannotComplete
    }

    // MARK: - AX helpers

    nonisolated private static func statusItems(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar = element(app, "AXExtrasMenuBar") else { return [] }
        AXUIElementSetMessagingTimeout(bar, 0.1)
        return elements(bar, kAXChildrenAttribute)
    }

    nonisolated private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = value(element, kAXPositionAttribute),
              let extent = value(element, kAXSizeAttribute),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    nonisolated private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref
    }

    nonisolated private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let ref = copy(element, attribute), CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    nonisolated private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    nonisolated private static func value(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let ref = copy(element, attribute), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXValue.self)
    }
}
