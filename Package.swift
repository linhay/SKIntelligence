// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SKIntelligence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SKIntelligence", targets: ["SKIntelligence"]),
        .library(name: "SKIClip", targets: ["SKIClip"]),
        .library(name: "SKITools", targets: ["SKITools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.1.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.11.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.3.0"),
        .package(url: "https://github.com/linhay/STJSON", from: "1.3.1"),
    ],
    targets: [
        .target(
            name: "SKIntelligence",
            dependencies: [
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
            ]
        ),
        .target(
            name: "SKITools",
            dependencies: [
                "SKIntelligence",
                "STJSON"
            ]
        ),
        .target(
            name: "SKIClip",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            resources: [
                .process("Resources/clip-merges.txt"),
                .process("Resources/clip-vocab.json")
            ],
            cSettings: [
                .define("ACCELERATE_NEW_LAPACK")
            ],
            swiftSettings: [
                .define("ACCELERATE_NEW_LAPACK")
            ]
        ),
        .testTarget(
            name: "SKIntelligenceTests",
            dependencies: [
                "SKIntelligence",
                "SKITools",
                "SKIClip",
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
            ]
        ),
    ]
)
