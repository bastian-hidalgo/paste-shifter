// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PasteShifter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PasteShifter", targets: ["PasteShifter"])],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "PasteShifter", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"])
    ]
)
