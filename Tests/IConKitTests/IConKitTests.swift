import Foundation
import IConKit
import Testing

struct ArrangementTests {
    @Test func hideAppendsByDefault() {
        var arrangement = Arrangement()
        arrangement.hide("a")
        arrangement.hide("b")
        #expect(arrangement.hidden == ["a", "b"])
    }

    @Test func hideInsertsBeforeTarget() {
        var arrangement = Arrangement(hidden: ["a", "b"])
        arrangement.hide("c", before: "b")
        #expect(arrangement.hidden == ["a", "c", "b"])
    }

    @Test func hidingAgainMovesTheApp() {
        var arrangement = Arrangement(hidden: ["a", "b", "c"])
        arrangement.hide("c", before: "a")
        #expect(arrangement.hidden == ["c", "a", "b"])
        arrangement.hide("c")
        #expect(arrangement.hidden == ["a", "b", "c"])
    }

    @Test func droppingOntoItselfDoesNothing() {
        var arrangement = Arrangement(hidden: ["a", "b"])
        arrangement.hide("a", before: "a")
        #expect(arrangement.hidden == ["a", "b"])
    }

    @Test func unknownTargetAppends() {
        var arrangement = Arrangement(hidden: ["a"])
        arrangement.hide("b", before: "zzz")
        #expect(arrangement.hidden == ["a", "b"])
    }

    @Test func showRemoves() {
        var arrangement = Arrangement(hidden: ["a", "b"])
        arrangement.show("a")
        #expect(arrangement.hidden == ["b"])
        #expect(!arrangement.isHidden("a"))
    }

    @Test func roundTripsThroughJSON() throws {
        let arrangement = Arrangement(hidden: ["x", "y"])
        let data = try JSONEncoder().encode(arrangement)
        #expect(try JSONDecoder().decode(Arrangement.self, from: data) == arrangement)
    }
}

struct AllowListTests {
    @Test func noRestrictionWhenNothingHiddenIsRunning() {
        #expect(AllowList.bundleIDs(running: ["a", "b"], hidden: [], own: "me") == nil)
        #expect(AllowList.bundleIDs(running: ["a", "b"], hidden: ["c"], own: "me") == nil)
    }

    @Test func excludesHiddenApps() {
        let allowed = AllowList.bundleIDs(running: ["a", "b", "c"], hidden: ["b"], own: "me")
        #expect(allowed == ["me", "a", "c"])
    }

    @Test func ownAppIsAlwaysAllowed() {
        let allowed = AllowList.bundleIDs(running: ["a", "me"], hidden: ["a", "me"], own: "me")
        #expect(allowed == ["me"])
    }

    @Test func revealedAppIsAllowed() {
        #expect(AllowList.bundleIDs(running: ["a", "b"], hidden: ["a", "b"], own: "me", revealed: "a") == ["me", "a"])
        #expect(AllowList.bundleIDs(running: ["a"], hidden: ["a"], own: "me", revealed: "a") == nil)
    }

    @Test func removesDuplicates() {
        let allowed = AllowList.bundleIDs(running: ["a", "a", "b"], hidden: ["b"], own: "me")
        #expect(allowed == ["me", "a"])
    }
}

struct AppLocationTests {
    @Test func applicationsFolderIsRecognized() {
        #expect(AppLocation.isRecognized(bundlePath: "/Applications/i-con.app"))
        #expect(AppLocation.isRecognized(bundlePath: "/Applications/Utilities/Tool.app"))
        #expect(AppLocation.isRecognized(bundlePath: "/System/Library/CoreServices/TextInputMenuAgent.app"))
    }

    @Test func otherFoldersAreNot() {
        #expect(!AppLocation.isRecognized(bundlePath: "/Users/me/Applications/SmartHub.app"))
        #expect(!AppLocation.isRecognized(bundlePath: "/Users/me/Projects/app/build/Release/App.app"))
        #expect(!AppLocation.isRecognized(bundlePath: "/private/tmp/Probe.app"))
        #expect(!AppLocation.isRecognized(bundlePath: "/ApplicationsBackup/App.app"))
    }
}
