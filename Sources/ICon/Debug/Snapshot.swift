import AppKit
import OSLog
import ScreenCaptureKit

/// Debugging aids for seeing what macOS actually draws in the menu bar. Launched through `open`,
/// a second i-con runs with its own Screen Recording permission, saves the image and quits:
///
///     open -g -n /Applications/i-con.app --args --snapshot /tmp/bar.png
///     open -g -n /Applications/i-con.app --args --snapshot-region x,y,w,h /tmp/region.png
enum Snapshot {
    nonisolated private static let logger = Logger(subsystem: "com.karembadawy.icon", category: "snapshot")

    /// Handles the debug arguments; returns false when there are none.
    static func handle(_ arguments: [String]) -> Bool {
        if let index = arguments.firstIndex(of: "--snapshot-region"), arguments.indices.contains(index + 2) {
            let numbers = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 4 else { return false }
            let region = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            Task {
                await snapshot(region: region, to: URL(filePath: arguments[index + 2]))
                NSApp.terminate(nil)
            }
            return true
        }
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            Task {
                await snapshot(to: URL(filePath: arguments[index + 1]))
                NSApp.terminate(nil)
            }
            return true
        }
        return false
    }

    /// Saves the main display's menu bar window, on white so transparent icons stay visible.
    nonisolated static func snapshot(to url: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
            // Each display has its own menu bar window; prefer the main display's (at the origin).
            let bars = content.windows.filter { $0.windowLayer == menuBarLevel && $0.frame.height < 60 && $0.frame.width > 200 }
            guard let bar = bars.first(where: { $0.frame.origin == .zero }) ?? bars.first else {
                logger.error("Snapshot: no menu bar window")
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: bar)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(bar.frame.width * scale)
            configuration.height = Int(bar.frame.height * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: image.width, pixelsHigh: image.height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Saves a screen region (global points, top-left origin), e.g. another display's menu bar.
    nonisolated static func snapshot(region: CGRect, to url: URL) async {
        do {
            let image = try await SCScreenshotManager.captureImage(in: region)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            logger.error("Region snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
