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
    private var controller: DividerController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.handle(CommandLine.arguments) { return }

        // Launch at Login and updates expect the copy in /Applications, not one on a disk image.
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

        controller = DividerController()
    }
}
