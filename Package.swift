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
        .library(name: "SKIClients", targets: ["SKIClients"]),
        .library(name: "SKIJSONRPC", targets: ["SKIJSONRPC"]),
        .library(name: "SKIACP", targets: ["SKIACP"]),
        .library(name: "SKIACPTransport", targets: ["SKIACPTransport"]),
        .library(name: "SKIACPClient", targets: ["SKIACPClient"]),
        .library(name: "SKIACPAgent", targets: ["SKIACPAgent"]),
        .library(name: "SKICLIShared", targets: ["SKICLIShared"]),
        .executable(name: "ski", targets: ["SKICLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.1.0"),
        .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.11.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.3.0"),
        .package(url: "https://github.com/linhay/SKProcessRunner", from: "0.0.17"),
        .package(url: "https://github.com/linhay/STJSON", from: "1.4.8"),
        .package(url: "https://github.com/linhay/STFilePath", from: "1.3.4"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.11.0")),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.2"),
        .package(url: "https://github.com/mattt/EventSource.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SKIJSONRPC"),
        .target(
            name: "SKIACP",
            dependencies: [
                "SKIJSONRPC"
            ]
        ),
        .target(
            name: "SKIACPTransport",
            dependencies: [
                "SKIJSONRPC"
            ]
        ),
        .target(
            name: "SKIACPClient",
            dependencies: [
                "SKIACP",
                "SKIACPTransport",
            ]
        ),
        .target(
            name: "SKIACPAgent",
            dependencies: [
                "SKIACP",
                "SKIntelligence",
            ]
        ),
        .target(
            name: "SKICLIShared",
            dependencies: [
                "SKIACPTransport",
                "SKIACPClient"
            ]
        ),
        .executableTarget(
            name: "SKICLI",
            dependencies: [
                "SKIACP",
                "SKIACPAgent",
                "SKIACPClient",
                "SKIACPTransport",
                "SKICLIShared",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "SKIntelligence",
            dependencies: [
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
                "STFilePath",
                "STJSON",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .target(
            name: "SKIClients",
            dependencies: [
                "SKIntelligence",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "EventSource", package: "EventSource"),
            ]
        ),
        .target(
            name: "SKITools",
            dependencies: [
                "SKIntelligence",
                "STJSON",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SKProcessRunner", package: "SKProcessRunner", condition: .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "SKIClip",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            resources: [
                .process("Resources/clip-merges.txt"),
                .process("Resources/clip-vocab.json"),
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
                "SKIClients",
                "SKITools",
                "SKIClip",
                "SKIJSONRPC",
                "SKIACP",
                "SKIACPTransport",
                "SKIACPClient",
                "SKIACPAgent",
                "SKICLIShared",
                .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            resources: [
                .process("Fixtures")
            ]
        ),
    ]
)
