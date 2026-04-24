// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DictImporter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "DictImporter",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/DictImporter"
        ),
        .testTarget(
            name: "DictImporterTests",
            dependencies: ["DictImporter"],
            path: "Tests/DictImporterTests"
        ),
    ]
)
