// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ICon",
    platforms: [.macOS("27.0")],
    targets: [
        // The only code that touches macOS 27's private menu bar API.
        .target(name: "MenuBarPrivate"),
        // Pure logic (arrangement, allow-list), unit tested.
        .target(name: "IConKit"),
        .executableTarget(
            name: "ICon",
            dependencies: ["IConKit", "MenuBarPrivate"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "IConKitTests", dependencies: ["IConKit"]),
    ]
)
