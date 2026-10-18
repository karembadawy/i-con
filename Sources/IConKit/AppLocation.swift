/// Where an app must live for macOS 27's menu bar restriction to recognize it.
/// While any icon is hidden, macOS hides the icons of apps outside these folders too, whatever
/// the allow-list says (verified with snapshots: `/Applications` works; `~/Applications` and other
/// folders don't).
public enum AppLocation {
    public static func isRecognized(bundlePath: String) -> Bool {
        bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix("/System/")
    }
}
