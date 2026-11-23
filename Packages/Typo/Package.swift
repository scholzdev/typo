// swift-tools-version:6.2
import PackageDescription

// One module per reason to change; dependencies point one way only:
// JSONRPC <- ACPProtocol, MCPProtocol; TypstEngine <- TypoKit <- TypoAssistant <- TypoACP (+ ACPProtocol); TypoKit <- TypoMCP (+ MCPProtocol).
let package = Package(
    name: "Typo",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "JSONRPC", targets: ["JSONRPC"]),
        .library(name: "ACPProtocol", targets: ["ACPProtocol"]),
        .library(name: "MCPProtocol", targets: ["MCPProtocol"]),
        .library(name: "TypstEngine", targets: ["TypstEngine"]),
        // Typo.app links this so Xcode builds TypstEngine as one framework that the app and typo-mcp share (project.yml).
        .library(name: "TypstEngineDynamic", type: .dynamic, targets: ["TypstEngine"]),
        .library(name: "TypoKit", targets: ["TypoKit"]),
        .library(name: "TypoAssistant", targets: ["TypoAssistant"]),
        .library(name: "TypoACP", targets: ["TypoACP"]),
        .library(name: "TypoMCP", targets: ["TypoMCP"]),
    ],
    targets: [
        .binaryTarget(name: "TypstBridge", path: "../../bridge/build/TypstBridge.xcframework"),
        .target(name: "JSONRPC"),
        .target(name: "ACPProtocol", dependencies: ["JSONRPC"]),
        .target(name: "MCPProtocol", dependencies: ["JSONRPC"]),
        .target(
            name: "TypstEngine",
            dependencies: ["TypstBridge"],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(name: "TypoKit", dependencies: ["TypstEngine"]),
        .target(name: "TypoAssistant", dependencies: ["TypoKit"]),
        .target(name: "TypoACP", dependencies: ["ACPProtocol", "TypoAssistant"]),
        .target(name: "TypoMCP", dependencies: ["MCPProtocol", "TypoKit"]),

        .target(name: "TypoTestSupport", dependencies: ["TypoKit", "TypstEngine"], path: "Tests/TypoTestSupport", resources: [.copy("Fixtures")]),
        .testTarget(name: "TypstEngineTests", dependencies: ["TypstEngine"]),
        .testTarget(name: "TypoKitTests", dependencies: ["TypoKit", "TypstEngine", "TypoTestSupport"]),
        .testTarget(name: "TypoAssistantTests", dependencies: ["TypoAssistant", "TypoTestSupport"]),
        .testTarget(name: "TypoACPTests", dependencies: ["TypoACP", "TypoTestSupport"]),
        .testTarget(name: "TypoMCPTests", dependencies: ["TypoMCP", "TypoTestSupport"]),
    ]
)
