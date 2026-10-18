// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ICon",
    platforms: [.macOS("27.0")],
    targets: [
        // Pure logic (the divider width), unit tested.
        .target(name: "IConKit"),
        .executableTarget(
            name: "ICon",
            dependencies: ["IConKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "IConKitTests", dependencies: ["IConKit"]),
    ]
)
