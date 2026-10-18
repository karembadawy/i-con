import AppKit

/// The ▾ button in the menu bar. Clicking it toggles the popup.
final class ChevronController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let state: AppState
    private let panel: PopupPanel
    private var lastClose = Date.distantPast

    init(state: AppState) {
        self.state = state
        panel = PopupPanel(rootView: PopupView(state: state))
        super.init()
        statusItem.autosaveName = "i-con.chevron"
        if let button = statusItem.button {
            button.image = Self.image(open: false)
            button.target = self
            button.action = #selector(toggle)
        }
        panel.onDismiss = { [weak self] in self?.didDismiss() }
        state.dismissPopup = { [weak self] in self?.panel.dismiss() }
    }

    func open() {
        state.popupWillOpen()
        panel.show(below: buttonFrame())
        statusItem.button?.image = Self.image(open: true)
        statusItem.button?.highlight(true)
    }

    @objc private func toggle() {
        if panel.isVisible {
            panel.dismiss()
        } else if Date().timeIntervalSince(lastClose) > 0.3 {
            // The click that closed the popup (via the outside-click monitor) shouldn't reopen it.
            open()
        }
    }

    private func didDismiss() {
        lastClose = Date()
        state.popupDidClose()
        statusItem.button?.image = Self.image(open: false)
        statusItem.button?.highlight(false)
    }

    /// The chevron's frame in AppKit screen coordinates, if it's placed in a menu bar.
    private func chevronFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Right after launch the button isn't placed yet; only trust a frame inside a menu bar.
        let isInMenuBar = NSScreen.screens.contains { screen in
            screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) && frame.minY >= screen.visibleFrame.maxY - 2
        }
        return isInMenuBar ? frame : nil
    }

    /// Where the popup hangs from, in AppKit screen coordinates.
    private func buttonFrame() -> NSRect {
        if let frame = chevronFrame() { return frame }
        // Clicks come from the menu bar, so the mouse is next to the chevron.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), mouse.y >= screen.visibleFrame.maxY {
            return NSRect(x: mouse.x - 12, y: screen.visibleFrame.maxY, width: 24, height: 24)
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return NSRect(x: screen.frame.maxX - 200, y: screen.visibleFrame.maxY, width: 24, height: 24)
    }

    private static func image(open: Bool) -> NSImage? {
        let image = NSImage(
            systemSymbolName: open ? "chevron.up" : "chevron.down",
            accessibilityDescription: open ? "Hide hidden icons" : "Show hidden icons"
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        image?.isTemplate = true
        return image
    }
}
