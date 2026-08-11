// swift-tools-version: 6.0
import PackageDescription

// One package, one target per module. The module boundaries and the dependency
// rule from docs/02 are enforced by the target graph below rather than by six
// separate packages: same isolation, one `swift test`, no cross-package
// resolution on every build. See PROJECT_STATE.md for the rationale.
let package = Package(
    name: "VigilKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VigilSupport", targets: ["VigilSupport"]),
        .library(name: "VigilCore", targets: ["VigilCore"]),
        .library(name: "VigilPower", targets: ["VigilPower"]),
        .library(name: "VigilSettings", targets: ["VigilSettings"]),
        .library(name: "VigilProviders", targets: ["VigilProviders"]),
        .library(name: "VigilHookBridge", targets: ["VigilHookBridge"]),
        .library(name: "VigilTipJar", targets: ["VigilTipJar"]),
    ],
    targets: [
        .target(name: "VigilSupport"),
        .target(name: "VigilCore", dependencies: ["VigilSupport"]),
        .target(name: "VigilPower", dependencies: ["VigilSupport"]),
        .target(name: "VigilSettings", dependencies: ["VigilSupport", "VigilCore"]),
        .target(name: "VigilProviders", dependencies: ["VigilSupport", "VigilCore"]),
        .target(name: "VigilHookBridge", dependencies: ["VigilSupport", "VigilCore"]),
        .target(name: "VigilTipJar", dependencies: ["VigilSupport"]),

        .testTarget(name: "VigilSupportTests", dependencies: ["VigilSupport"]),
        .testTarget(name: "VigilCoreTests", dependencies: ["VigilCore"]),
        .testTarget(name: "VigilPowerTests", dependencies: ["VigilPower"]),
        .testTarget(name: "VigilSettingsTests", dependencies: ["VigilSettings"]),
        .testTarget(
            name: "VigilProvidersTests",
            dependencies: ["VigilProviders"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "VigilHookBridgeTests", dependencies: ["VigilHookBridge"]),
        .testTarget(name: "VigilTipJarTests", dependencies: ["VigilTipJar"]),

        // Spans provider → bus → coordinator → power backend. docs/08 asks for
        // the hold/release timeline to be asserted end to end, and no
        // single-module test target can import all four.
        .testTarget(
            name: "VigilIntegrationTests",
            dependencies: ["VigilProviders", "VigilCore", "VigilPower"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
