// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentSessionManager",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.18.0"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentSessionManager",
            dependencies: [
                "AgentSessionManagerMCPBridgeCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift"),
                .product(name: "SignPostIntegration", package: "opentelemetry-swift"),
                .product(name: "ResourceExtension", package: "opentelemetry-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Sources/AgentSessionManager",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "AgentSessionManagerMCPBridgeCore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Sources/AgentSessionManagerMCPBridgeCore"
        ),
        .executableTarget(
            name: "AgentSessionManagerMCPBridge",
            dependencies: [
                "AgentSessionManagerMCPBridgeCore"
            ],
            path: "Sources/AgentSessionManagerMCPBridge"
        ),
        .testTarget(
            name: "AgentSessionManagerTests",
            dependencies: [
                "AgentSessionManager",
                "AgentSessionManagerMCPBridgeCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Tests",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])]
        )
    ],
    swiftLanguageModes: [.v6]
)
