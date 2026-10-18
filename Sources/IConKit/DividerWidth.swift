import CoreGraphics

/// How wide i-con's blank divider must be. macOS 27 tucks menu bar icons that don't fit behind its
/// « button, starting from the left. A divider just too wide to fit between the notch and i-con's
/// mark gets tucked away, and with it every icon to its left. Too wide and macOS drops « as well
/// (seen with 700pt on a 1470pt screen), so the divider stays as narrow as that allows.
public enum DividerWidth {
    /// The smallest width that still can't fit, so it always acts as a wall.
    public static let minimum: CGFloat = 24

    /// - Parameters:
    ///   - markOffsetFromRight: distance from the screen's right edge to the left edge of i-con's
    ///     mark. Icons are laid out from the right, so it's the same on every display.
    ///   - screenWidth: width of the notched screen.
    ///   - notchRight: distance from that screen's left edge to the notch's right edge.
    ///   - margin: extra width so rounding and item spacing can't let the divider squeeze in.
    public static func width(markOffsetFromRight: CGFloat, screenWidth: CGFloat, notchRight: CGFloat, margin: CGFloat = 12) -> CGFloat {
        let freeSpace = screenWidth - markOffsetFromRight - notchRight
        // macOS discards a status item whose width reaches half the screen.
        let maximum = screenWidth / 2 - 1
        return min(max(freeSpace + margin, minimum), maximum)
    }
}
