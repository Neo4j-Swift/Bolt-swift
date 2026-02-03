// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Bolt",

    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
    ],

    products: [
        .library(name: "Bolt", targets: ["Bolt"]),
    ],

    dependencies: [
        .package(path: "../PackStream-Swift"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
    ],

    targets: [
        .target(
            name: "Bolt",
            dependencies: [
                .product(name: "PackStream", package: "PackStream-Swift"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BoltTests",
            dependencies: ["Bolt"]
        ),
    ]
)
