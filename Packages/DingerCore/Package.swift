// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DingerCore",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        // The app consumes the core statically, so iOS has no runtime
        // framework to embed or code-sign. The Android JNI bridge remains a
        // dynamic product because Android loads it with System.loadLibrary.
        .library(name: "DingerCore", type: .static, targets: ["DingerCore"]),
        .library(name: "DingerAndroidBridge", type: .dynamic, targets: ["DingerAndroidBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.10.0"),
    ],
    targets: [
        .target(
            name: "DingerCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "DingerAndroidBridge",
            dependencies: ["DingerCore"]
        ),
        .testTarget(
            name: "DingerCoreTests",
            dependencies: [
                "DingerCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
