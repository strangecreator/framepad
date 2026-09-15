// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framepad",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Framepad", targets: ["Framepad"])],
    targets: [
        .target(name: "FramepadCore"),
        .executableTarget(name: "Framepad", dependencies: ["FramepadCore"]),
        .testTarget(name: "FramepadCoreTests", dependencies: ["FramepadCore"])
    ]
)
