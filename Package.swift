// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PasteShifter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PasteShifter", targets: ["PasteShifter"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.12.3"))
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "PasteShifter", dependencies: [
            "ClipboardCore",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "X509", package: "swift-certificates")
        ]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"])
    ]
)
