// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BookRoom",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "BookRoom", targets: ["BookRoom"])
    ],
    dependencies: [
        // SQLite wrapper
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // ZIP compression for backup/export
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        // Image loading and caching
        .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0")
    ],
    targets: [
        .target(
            name: "BookRoom",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Nuke", package: "Nuke")
            ],
            path: "BookRoom"
        ),
        .testTarget(
            name: "BookRoomTests",
            dependencies: ["BookRoom"],
            path: "BookRoomTests"
        )
    ]
)
