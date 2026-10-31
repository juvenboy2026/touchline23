// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NXPackagingGUI",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NXPackagingGUI", targets: ["NXPackagingGUI"])],
    targets: [
        .target(name: "PackagingModel"),
        .executableTarget(name: "NXPackagingGUI", dependencies: ["PackagingModel"]),
        .testTarget(name: "PackagingModelTests", dependencies: ["PackagingModel"])
    ]
)
