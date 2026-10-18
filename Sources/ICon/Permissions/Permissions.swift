import AppKit
import ApplicationServices

/// Accessibility is required (finding and pressing items). Screen Recording is optional:
/// without it the popup shows app icons instead of the real menu bar icons.
@Observable
final class Permissions {
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
    }

    func promptForAccessibility() {
        // "AXTrustedCheckOptionPrompt" is kAXTrustedCheckOptionPrompt.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    /// Some permission changes only apply to a fresh process.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
