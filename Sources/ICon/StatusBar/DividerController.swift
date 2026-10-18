import AppKit
import IConKit
import OSLog
import ServiceManagement

/// i-con's two menu bar items: the mark, which is the visible icon, and a blank divider right
/// against its left side. The divider is sized to be just too wide to fit next to the notch, so
/// macOS tucks it behind «, and with it every icon left of the mark. Clicking « shows them.
final class DividerController: NSObject, NSMenuDelegate {
    private static let markName = "i-con.mark"
    private static let dividerName = "i-con.divider"

    private let mark: NSStatusItem
    private var divider: NSStatusItem
    private var dividerAnchoredAt: Double
    private let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let noNotchNote = NSMenuItem(title: "No notched screen, so nothing needs tucking away", action: nil, keyEquivalent: "")
    private let logger = Logger(subsystem: "com.karembadawy.icon", category: "divider")

    override init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.positionKey(Self.markName)) == nil {
            // First launch: near the right, so the clock, Control Center and a few icons stay visible.
            defaults.set(400.0, forKey: Self.positionKey(Self.markName))
        }
        mark = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mark.autosaveName = Self.markName
        dividerAnchoredAt = Self.markPosition
        divider = Self.makeDivider(nextTo: dividerAnchoredAt)
        super.init()

        if let button = mark.button {
            button.image = NSImage(systemSymbolName: "chevron.left.to.line", accessibilityDescription: "i-con: icons to the left are tucked behind «")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            button.image?.isTemplate = true
            button.toolTip = "Icons left of this mark are tucked behind «"
        }
        mark.menu = makeMenu()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // macOS saves the mark's new position in our defaults when it's ⌘-dragged.
        center.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)

        // The mark moves whenever icons to its right appear, disappear or change width.
        Task { [weak self] in
            while let self {
                self.updateWidth()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Divider

    private static func positionKey(_ name: String) -> String {
        "NSStatusItem Preferred Position \(name)"
    }

    private static var markPosition: Double {
        UserDefaults.standard.double(forKey: positionKey(markName))
    }

    /// Saved positions count from the right edge, so a slightly larger value sits just left of the mark.
    private static func makeDivider(nextTo markPosition: Double) -> NSStatusItem {
        UserDefaults.standard.set(markPosition + 0.5, forKey: positionKey(dividerName))
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.autosaveName = dividerName
        item.button?.title = ""
        item.button?.isEnabled = false
        return item
    }

    @objc private func defaultsChanged() {
        // Keep the divider glued to the mark after the mark is dragged somewhere else.
        guard Self.markPosition != dividerAnchoredAt else { return }
        dividerAnchoredAt = Self.markPosition
        let length = divider.length
        NSStatusBar.system.removeStatusItem(divider)
        divider = Self.makeDivider(nextTo: dividerAnchoredAt)
        divider.length = length
        logger.info("Mark moved; divider re-placed next to it")
    }

    @objc private func screensChanged() {
        updateWidth()
    }

    private func updateWidth() {
        guard let notched = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }),
              let rightOfNotch = notched.auxiliaryTopRightArea
        else {
            setDividerLength(0)
            return
        }
        guard let frame = markFrame(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else { return }
        // The mark sits in the active menu bar. On a screen without a notch there's room to spare,
        // and a divider would only show up as a blank gap.
        guard screen.auxiliaryTopRightArea != nil else {
            setDividerLength(0)
            return
        }
        let width = DividerWidth.width(
            markOffsetFromRight: screen.frame.maxX - frame.minX,
            screenWidth: notched.frame.width,
            notchRight: notched.frame.width - rightOfNotch.width
        )
        setDividerLength(width)
    }

    private func setDividerLength(_ length: CGFloat) {
        guard abs(divider.length - length) > 1 else { return }
        divider.length = length
        logger.info("Divider width \(Int(length))pt")
    }

    /// The mark's frame in AppKit screen coordinates, if it's placed in a visible menu bar.
    private func markFrame() -> NSRect? {
        guard let button = mark.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let inMenuBar = NSScreen.screens.contains { screen in
            screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) && frame.minY >= screen.visibleFrame.maxY - 2
        }
        return inMenuBar ? frame : nil
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for line in [
            "Icons left of this mark are tucked behind «.",
            "To move an icon, hold ⌘ and drag it across the mark.",
            "Keep it inside the menu bar: dropping it below deletes it.",
        ] {
            menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
        }
        noNotchNote.isHidden = true
        menu.addItem(noNotchNote)
        menu.addItem(.separator())
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit i-con", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        noNotchNote.isHidden = NSScreen.screens.contains { $0.auxiliaryTopRightArea != nil }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
