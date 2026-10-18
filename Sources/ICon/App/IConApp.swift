import AppKit

@main
struct IConApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var chevron: ChevronController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot-region"), arguments.indices.contains(index + 2) {
            let numbers = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            if numbers.count == 4 {
                let region = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                Task {
                    await IconCapture.snapshot(region: region, to: URL(filePath: arguments[index + 2]))
                    NSApp.terminate(nil)
                }
                return
            }
        }
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            Task {
                await IconCapture.snapshot(to: URL(filePath: arguments[index + 1]))
                NSApp.terminate(nil)
            }
            return
        }

        // macOS matches the allow-list against the copy LaunchServices knows for the bundle ID,
        // so a copy opened from the disk image (or anywhere else) would hide its own chevron.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            let alert = NSAlert()
            alert.messageText = "Move i-con to Applications"
            alert.informativeText = "i-con only works from the Applications folder. Drag it there, then open it from Applications."
            alert.addButton(withTitle: "Quit")
            NSApp.activate()
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let state = AppState()
        let chevron = ChevronController(state: state)
        self.state = state
        self.chevron = chevron
        state.start()
        if !state.permissions.accessibility {
            // Show the onboarding once the chevron has been placed in the menu bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { chevron.open() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // macOS restores the menu bar when the process exits anyway; this is just tidy.
        state?.stop()
    }
}
