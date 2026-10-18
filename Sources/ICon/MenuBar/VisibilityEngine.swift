import Foundation
import IConKit
import MenuBarPrivate
import OSLog

/// Hides apps' status items with macOS 27's menu bar restriction (see `IMBVisibilityShim`).
final class VisibilityEngine {
    enum State: Equatable {
        /// Nothing is hidden.
        case inactive
        /// The restriction is applied.
        case active
        /// The private API is missing or failed; nothing is hidden.
        case unavailable(String)
    }

    private let shim = IMBVisibilityShim()
    private let systemItems = AllowList.systemItems.map { NSNumber(value: $0) }
    private let logger = Logger(subsystem: "com.karembadawy.icon", category: "visibility")

    /// Applies an allow-list; nil removes the restriction.
    func apply(allowedBundleIDs: [String]?) async -> State {
        guard let allowed = allowedBundleIDs else {
            shim.invalidate()
            return .inactive
        }
        if let reason = IMBVisibilityShim.unavailableReason {
            logger.error("Hiding unavailable: \(reason, privacy: .public)")
            return .unavailable(reason)
        }
        let failure: String? = await withCheckedContinuation { continuation in
            shim.applyAllowedBundleIDs(allowed, systemItems: systemItems) { error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
        if let failure {
            // Fail safe: show everything rather than hide the wrong items.
            shim.invalidate()
            logger.error("Restriction failed: \(failure, privacy: .public)")
            return .unavailable(failure)
        }
        logger.debug("Restriction applied, \(allowed.count) apps allowed")
        return .active
    }

    func reset() {
        shim.invalidate()
    }
}
