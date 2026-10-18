import CoreGraphics
import IConKit
import Testing

struct DividerWidthTests {
    // A 13" MacBook screen: 1470pt wide, notch ending 824.5pt from the left.
    let screenWidth: CGFloat = 1470
    let notchRight: CGFloat = 824.5

    @Test func fillsTheGapBetweenNotchAndMark() {
        // Mark 560pt from the right leaves 85.5pt free right of the notch.
        let width = DividerWidth.width(markOffsetFromRight: 560, screenWidth: screenWidth, notchRight: notchRight)
        #expect(width == 85.5 + 12)
    }

    @Test func growsWhenMoreIconsAreHidden() {
        // Fewer visible icons put the mark further right, leaving more room to fill.
        let few = DividerWidth.width(markOffsetFromRight: 300, screenWidth: screenWidth, notchRight: notchRight)
        let many = DividerWidth.width(markOffsetFromRight: 560, screenWidth: screenWidth, notchRight: notchRight)
        #expect(few > many)
    }

    @Test func neverReachesHalfTheScreen() {
        let width = DividerWidth.width(markOffsetFromRight: 10, screenWidth: screenWidth, notchRight: 0)
        #expect(width == screenWidth / 2 - 1)
    }

    @Test func staysAWallWhenTheBarIsAlreadyFull() {
        // Mark left of the notch: no free space, but the divider still can't fit.
        let width = DividerWidth.width(markOffsetFromRight: 700, screenWidth: screenWidth, notchRight: notchRight)
        #expect(width == DividerWidth.minimum)
    }
}
