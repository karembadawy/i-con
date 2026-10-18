/// Builds the allow-list for macOS 27's menu bar restriction: every app not listed
/// loses its status items, so the list is "everything running except hidden apps".
public enum AllowList {
    /// System item IDs (clock = 2, sound = 5, Wi-Fi = 6, Control Center = 8, …).
    /// All of them are allowed so Apple's own items stay under macOS control.
    public static let systemItems = Array(0..<64)

    /// Returns the bundle IDs to allow, or nil when no hidden app is running
    /// (then no restriction is needed at all).
    /// - Parameters:
    ///   - running: bundle IDs of every running app.
    ///   - hidden: bundle IDs the user hid.
    ///   - own: this app's bundle ID; always allowed so the chevron stays visible.
    ///   - revealed: a hidden app temporarily shown so it can be clicked.
    public static func bundleIDs(running: [String], hidden: [String], own: String, revealed: String? = nil) -> [String]? {
        var hiddenSet = Set(hidden)
        hiddenSet.remove(own)
        if let revealed { hiddenSet.remove(revealed) }
        guard running.contains(where: hiddenSet.contains) else { return nil }

        var seen = Set<String>()
        return ([own] + running).filter { !hiddenSet.contains($0) && seen.insert($0).inserted }
    }
}
