import AppKit
import OSLog
import ScreenCaptureKit

nonisolated struct CaptureTarget: Sendable {
    let id: String
    /// Global screen coordinates, top-left origin.
    let frame: CGRect
}

/// Captures menu bar icons with ScreenCaptureKit. macOS 27 draws the whole menu bar in one
/// window and doesn't draw hidden items, so only visible items can be captured.
enum IconCapture {
    nonisolated private static let logger = Logger(subsystem: "com.karembadawy.icon", category: "capture")

    /// Debugging aid: saves the menu bar exactly as macOS draws it, on a white background.
    /// Run `open -n /Applications/i-con.app --args --snapshot /path/menubar.png`; launched that
    /// way it uses i-con's own Screen Recording permission.
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
            logger.info("Snapshot of \(NSStringFromRect(bar.frame), privacy: .public) saved")
        } catch {
            logger.error("Snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Debugging aid: saves a screen region (global points, top-left origin), e.g. a menu that
    /// another app opened. `open -g -n /Applications/i-con.app --args --snapshot-region x,y,w,h out.png`
    nonisolated static func snapshot(region: CGRect, to url: URL) async {
        do {
            let image = try await SCScreenshotManager.captureImage(in: region)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            logger.error("Region snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func capture(_ targets: [CaptureTarget]) async throws -> [String: CGImage] {
        guard !targets.isEmpty else { return [:] }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // On macOS 27 the menu bar is a Window Server window at the main menu level.
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let bars = content.windows.filter {
            $0.windowLayer == menuBarLevel && $0.frame.height < 60 && $0.frame.width > 200
        }

        var images: [String: CGImage] = [:]
        var remaining = targets

        // Capturing the bar window alone gives icons without the wallpaper behind them.
        for bar in bars {
            let inside = remaining.filter { bar.frame.contains($0.frame) }
            guard !inside.isEmpty else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: bar)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(bar.frame.width * scale)
            configuration.height = Int(bar.frame.height * scale)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            for target in inside {
                let rect = target.frame.offsetBy(dx: -bar.frame.minX, dy: -bar.frame.minY)
                if let crop = crop(image, to: rect, scale: scale) {
                    images[target.id] = crop
                }
            }
            remaining.removeAll { target in inside.contains { $0.id == target.id } }
        }

        // Fallback: a plain screenshot of each item's area.
        for target in remaining {
            if let image = try? await SCScreenshotManager.captureImage(in: target.frame) {
                images[target.id] = image
            }
        }
        logger.info("Captured \(images.count) of \(targets.count) icons (\(bars.count) bar windows)")
        return images
    }

    nonisolated private static func crop(_ image: CGImage, to rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        return image.cropping(to: pixels.integral)
    }

    /// True when nothing is drawn: the item had a frame but macOS didn't draw it there.
    nonisolated static func isBlank(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return true }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        return !stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] >= 24 }
    }

    /// True for single-color icons on a transparent background (most menu bar icons). Those are
    /// drawn as templates in the popup so they stay readable in light and dark mode. Two-tone
    /// icons (a badge with a letter cut in) keep their colors, or the letter would vanish.
    nonisolated static func looksLikeTemplate(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }

        var opaque = 0, transparent = 0, colorful = 0
        var brightness = [Int](repeating: 0, count: 256)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha >= 24 else { transparent += 1; continue }
            opaque += 1
            let red = min(Int(pixels[index]) * 255 / alpha, 255)
            let green = min(Int(pixels[index + 1]) * 255 / alpha, 255)
            let blue = min(Int(pixels[index + 2]) * 255 / alpha, 255)
            if max(red, green, blue) - min(red, green, blue) > 48 { colorful += 1 }
            brightness[(red * 299 + green * 587 + blue * 114) / 1000] += 1
        }
        guard transparent > 0, opaque > 0, colorful * 20 < opaque else { return false }
        return percentile(0.9, of: brightness, total: opaque) - percentile(0.1, of: brightness, total: opaque) <= 40
    }

    nonisolated private static func percentile(_ fraction: Double, of histogram: [Int], total: Int) -> Int {
        let target = Int(Double(total) * fraction)
        var count = 0
        for (level, pixels) in histogram.enumerated() {
            count += pixels
            if count > target { return level }
        }
        return histogram.count - 1
    }
}

/// Captured icons, kept on disk so hidden apps still show their real icon after a relaunch.
@Observable
final class IconCache {
    struct Icon {
        let image: NSImage
        let isTemplate: Bool
    }

    private(set) var captured: [String: Icon] = [:]
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    /// Apps whose capture came out blank (not drawn), so they aren't recaptured on every refresh.
    @ObservationIgnored private var blank: Set<String> = []
    @ObservationIgnored private let directory: URL

    init() {
        directory = URL.applicationSupportDirectory.appending(path: "i-con/icons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    func hasCapture(_ bundleID: String) -> Bool {
        captured[bundleID] != nil
    }

    /// No capture yet, and no blank attempt since apps last launched or quit.
    func needsCapture(_ bundleID: String) -> Bool {
        captured[bundleID] == nil && !blank.contains(bundleID)
    }

    func forgetBlankCaptures() {
        blank.removeAll()
    }

    /// The captured menu bar icon, or the app icon until one is captured.
    func icon(for item: MenuBarItem) -> Icon {
        if let icon = captured[item.bundleID] { return icon }
        if let image = appIcons[item.bundleID] { return Icon(image: image, isTemplate: false) }
        let image = (NSRunningApplication(processIdentifier: item.pid)?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil))?.copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        appIcons[item.bundleID] = image
        return Icon(image: image, isTemplate: false)
    }

    /// Stores captures; `sizes` are the items' sizes in points.
    func store(_ images: [String: CGImage], sizes: [String: CGSize]) {
        for (bundleID, cgImage) in images {
            guard let size = sizes[bundleID] else { continue }
            // A blank capture would show as an empty tile; the app icon is better.
            if IconCapture.isBlank(cgImage) {
                blank.insert(bundleID)
                continue
            }
            blank.remove(bundleID)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = size
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            captured[bundleID] = Icon(image: image, isTemplate: IconCapture.looksLikeTemplate(cgImage))
            try? rep.representation(using: .png, properties: [:])?.write(to: fileURL(bundleID), options: .atomic)
        }
    }

    private func loadFromDisk() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" {
            guard let image = NSImage(contentsOf: file),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { continue }
            if IconCapture.isBlank(cgImage) {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            captured[file.deletingPathExtension().lastPathComponent] = Icon(image: image, isTemplate: IconCapture.looksLikeTemplate(cgImage))
        }
    }

    private func fileURL(_ bundleID: String) -> URL {
        directory.appending(path: "\(bundleID).png")
    }
}
