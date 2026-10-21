// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipster",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic (store, hotkey state machine) — no AppKit, unit-tested.
        .target(name: "ClipsterCore"),
        .executableTarget(name: "Clipster", dependencies: ["ClipsterCore"]),
        .testTarget(name: "ClipsterCoreTests", dependencies: ["ClipsterCore"]),
    ]
)
