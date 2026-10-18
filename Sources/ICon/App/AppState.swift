import AppKit
import IConKit
import OSLog
import ServiceManagement

@Observable
final class AppState {
    enum Section {
        case hidden
        case menuBar
    }

    let permissions = Permissions()
    let icons = IconCache()
    private(set) var items: [MenuBarItem] = []
    private(set) var arrangement: Arrangement
    private(set) var engineState: VisibilityEngine.State = .inactive
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var isEditing = false

    /// Closes the popup; set by the chevron.
    @ObservationIgnored var dismissPopup: (() -> Void)?

    @ObservationIgnored private let engine = VisibilityEngine()
    @ObservationIgnored private let activator = ItemActivator()
    @ObservationIgnored private let clockClicks = ClockClickHandler()
    /// Hiding is paused while Notification Center is open (the restriction blocks it).
    @ObservationIgnored private var hidingSuspended = false
    @ObservationIgnored private let store = ArrangementStore()
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.karembadawy.icon"
    @ObservationIgnored private var systemFrames: [CGRect] = []
    @ObservationIgnored private var revealedID: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var applyGeneration = 0
    @ObservationIgnored private var rescan: Task<Void, Never>?
    @ObservationIgnored private var runningAppsObservation: NSKeyValueObservation?
    @ObservationIgnored private let logger = Logger(subsystem: "com.karembadawy.icon", category: "state")

    init() {
        arrangement = store.load()
        activator.state = self
        clockClicks.state = self
    }

    /// Hidden apps that are running, in popup order.
    var hiddenItems: [MenuBarItem] {
        let byID = Dictionary(items.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        return arrangement.hidden.compactMap { byID[$0] }
    }

    /// Apps meant to be visible that macOS hides anyway while the restriction is on, because
    /// they aren't installed in /Applications.
    var appsMacOSWillHide: [MenuBarItem] {
        guard engineState == .active else { return [] }
        return visibleItems.filter { !AppLocation.isRecognized(bundlePath: $0.bundlePath) }
    }

    /// Apps shown in the menu bar, left to right.
    var visibleItems: [MenuBarItem] {
        items.filter { !arrangement.isHidden($0.bundleID) }.sorted { $0.frame.minX < $1.frame.minX }
    }

    // MARK: - Lifecycle

    func start() {
        if !permissions.accessibility {
            permissions.promptForAccessibility()
        }
        // Permissions can change at any time in System Settings.
        Task {
            while true {
                permissions.refresh()
                if permissions.accessibility && !started { begin() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        engine.reset()
    }

    private func begin() {
        started = true
        logger.info("Accessibility granted, starting")
        observeRunningApps()
        clockClicks.start()
        Task {
            // Nothing is hidden yet, so every icon can be captured.
            await refresh(captureAll: true)
            await applyVisibility()
            // Apps can add or remove items without launching or quitting.
            while true {
                try? await Task.sleep(for: .seconds(30))
                await refresh()
            }
        }
    }

    private func observeRunningApps() {
        // NSWorkspace's launch notifications skip menu-bar-only (LSUIElement) apps, which are
        // exactly the apps with status items. The running-apps list itself is key-value
        // observable and covers every app.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.runningAppsChanged() }
        }
    }

    private func runningAppsChanged() {
        icons.forgetBlankCaptures()
        // New apps must join the allow-list before their status item shows up, or they'd start
        // hidden. This also hides a hidden app that just launched, or drops the restriction once
        // none is running.
        Task { await applyVisibility() }
        // A new app's status item shows up a moment after launch; rescan to pick it up.
        rescan?.cancel()
        rescan = Task {
            for delay in [2, 6] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    // MARK: - Scanning

    /// Rescans the menu bar. Captures icons that are missing, or every visible icon with `captureAll`.
    func refresh(captureAll: Bool = false) async {
        guard permissions.accessibility else { return }
        update(with: await AXInventory.scan(AXInventory.runningApps()))
        logger.debug("Found \(self.items.count) apps with menu bar items")
        let ids = items.map(\.bundleID).filter { captureAll || icons.needsCapture($0) }
        await captureIcons(for: Set(ids))
    }

    func captureIcons(for ids: Set<String>, waitForLayout: Bool = true) async {
        guard permissions.screenRecording, !ids.isEmpty else { return }
        if waitForLayout {
            await waitForSettledLayout()
        } else {
            update(with: await AXInventory.scan(AXInventory.runningApps()))
        }
        // Hidden apps report stale frames, so they're left out of the obstacles.
        let visible = items.filter { !isCurrentlyHidden($0.bundleID) }
        let targets = visible.filter { item in
            let obstacles = systemFrames + visible.filter { $0.bundleID != item.bundleID }.flatMap(\.frames)
            return ids.contains(item.bundleID) && MenuBarGeometry.isCapturable(item.frame, obstacles: obstacles)
        }
        guard !targets.isEmpty else { return }
        do {
            let images = try await IconCapture.capture(targets.map { CaptureTarget(id: $0.bundleID, frame: $0.frame) })
            icons.store(images, sizes: Dictionary(targets.map { ($0.bundleID, $0.frame.size) }, uniquingKeysWith: { first, _ in first }))
        } catch {
            logger.error("Icon capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Icons slide into place after the menu bar changes (e.g. right after launch, when the
    /// previous restriction is gone). Rescans until two scans in a row agree.
    private func waitForSettledLayout() async {
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(150))
            let before = layout
            update(with: await AXInventory.scan(AXInventory.runningApps()))
            if layout == before { return }
        }
        logger.debug("Menu bar layout didn't settle")
    }

    private var layout: [String: [CGRect]] {
        var layout = Dictionary(items.map { ($0.bundleID, $0.frames) }, uniquingKeysWith: { first, _ in first })
        layout[AXInventory.systemBundleID] = systemFrames
        return layout
    }

    private func update(with scanned: [MenuBarItem]) {
        items = scanned.filter { $0.bundleID != AXInventory.systemBundleID }
        systemFrames = scanned.filter { $0.bundleID == AXInventory.systemBundleID }.flatMap(\.frames)
    }

    private func isCurrentlyHidden(_ bundleID: String) -> Bool {
        engineState == .active && arrangement.isHidden(bundleID) && bundleID != revealedID
    }

    // MARK: - Hiding

    func applyVisibility() async {
        guard permissions.accessibility else { return }
        applyGeneration += 1
        let generation = applyGeneration
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let allowed = hidingSuspended
            ? nil
            : AllowList.bundleIDs(running: running, hidden: arrangement.hidden, own: ownBundleID, revealed: revealedID)
        let state = await engine.apply(allowedBundleIDs: allowed)
        guard generation == applyGeneration else { return }
        if state != engineState { logger.info("Hiding: \(String(describing: state), privacy: .public)") }
        engineState = state
    }

    func setHidingSuspended(_ suspended: Bool) async {
        hidingSuspended = suspended
        await applyVisibility()
    }

    /// Whether a point (global, top-left origin) is on the clock: the rightmost system item in
    /// its menu bar.
    func isClock(at point: CGPoint) -> Bool {
        guard let frame = systemFrames.first(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }) else { return false }
        return systemFrames
            .filter { abs($0.midY - frame.midY) < 20 }
            .allSatisfy { $0.maxX <= frame.maxX + 1 }
    }

    func setRevealed(_ bundleID: String?) async {
        revealedID = bundleID
        await applyVisibility()
    }

    /// Handles a drop of `ids` onto a row, before the tile `target` (or at the end).
    func drop(_ ids: [String], into section: Section, before target: String?) -> Bool {
        guard let id = ids.first, items.contains(where: { $0.bundleID == id }) else { return false }
        switch section {
        case .hidden: hide(id, before: target)
        case .menuBar: show(id)
        }
        return true
    }

    func hide(_ bundleID: String, before target: String? = nil) {
        // Capture while it's still visible so the popup shows the real icon.
        let needsCapture = !icons.hasCapture(bundleID)
        arrangement.hide(bundleID, before: target)
        store.save(arrangement)
        Task {
            if needsCapture { await captureIcons(for: [bundleID]) }
            await applyVisibility()
        }
    }

    func show(_ bundleID: String) {
        guard arrangement.isHidden(bundleID) else { return }
        arrangement.show(bundleID)
        store.save(arrangement)
        Task {
            await applyVisibility()
            // Let it reappear before capturing.
            try? await Task.sleep(for: .milliseconds(300))
            await captureIcons(for: [bundleID])
        }
    }

    // MARK: - Popup

    func activate(_ item: MenuBarItem) {
        // The item's own menu opens from the menu bar, right where the popup was.
        dismissPopup?()
        activator.activate(item)
    }

    func popupWillOpen() {
        activator.endReveal()
        permissions.refresh()
        if started { Task { await refresh() } }
    }

    func popupDidClose() {
        isEditing = false
    }

    func setEditing(_ editing: Bool) {
        isEditing = editing
        // Fresh images for the "Menu bar" row.
        if editing, started { Task { await refresh(captureAll: true) } }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
