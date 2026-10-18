/// Which apps the user moved into the popup, in popup order.
/// Apps not listed stay in the menu bar.
public struct Arrangement: Codable, Equatable, Sendable {
    /// Bundle IDs of hidden apps, in the order they appear in the popup.
    public private(set) var hidden: [String]

    public init(hidden: [String] = []) {
        self.hidden = hidden
    }

    public func isHidden(_ bundleID: String) -> Bool {
        hidden.contains(bundleID)
    }

    /// Hides `bundleID`, placing it before `target` in the popup (or at the end).
    /// Hiding an already hidden app moves it.
    public mutating func hide(_ bundleID: String, before target: String? = nil) {
        guard bundleID != target else { return }
        hidden.removeAll { $0 == bundleID }
        if let target, let index = hidden.firstIndex(of: target) {
            hidden.insert(bundleID, at: index)
        } else {
            hidden.append(bundleID)
        }
    }

    public mutating func show(_ bundleID: String) {
        hidden.removeAll { $0 == bundleID }
    }
}
