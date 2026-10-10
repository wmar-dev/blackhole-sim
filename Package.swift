// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "blackhole-sim",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BlackHoleKit", targets: ["BlackHoleKit"]),
        .executable(name: "bhsim", targets: ["bhsim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "BlackHoleKit",
            // The physics core is compute-bound; unoptimized builds are ~100x slower and make the test
            // suite impractical, so optimize it even in debug builds.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "bhsim",
            dependencies: [
                "BlackHoleKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "BlackHoleKitTests",
            dependencies: ["BlackHoleKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
