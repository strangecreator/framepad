// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framepad",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Framepad", targets: ["Framepad"])],
    targets: [
        .target(name: "FramepadCore", path: "sources/framepad-core"),
        .executableTarget(name: "Framepad", dependencies: ["FramepadCore"], path: "sources/framepad"),
        .testTarget(name: "FramepadCoreTests", dependencies: ["FramepadCore"], path: "tests/framepad-core-tests")
    ]
)
