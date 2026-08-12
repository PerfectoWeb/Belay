// swift-tools-version: 6.0
import PackageDescription

// One package, one target per module. The module boundaries and the dependency
// rule from docs/02 are enforced by the target graph below rather than by six
// separate packages: same isolation, one `swift test`, no cross-package
// resolution on every build. See PROJECT_STATE.md for the rationale.
let package = Package(
    name: "BelayKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BelaySupport", targets: ["BelaySupport"]),
        .library(name: "BelayCore", targets: ["BelayCore"]),
        .library(name: "BelayPower", targets: ["BelayPower"]),
        .library(name: "BelaySettings", targets: ["BelaySettings"]),
        .library(name: "BelayProviders", targets: ["BelayProviders"]),
        .library(name: "BelayHookBridge", targets: ["BelayHookBridge"]),
        .library(name: "BelayTipJar", targets: ["BelayTipJar"]),
    ],
    targets: [
        .target(name: "BelaySupport"),
        .target(name: "BelayCore", dependencies: ["BelaySupport"]),
        .target(name: "BelayPower", dependencies: ["BelaySupport"]),
        .target(name: "BelaySettings", dependencies: ["BelaySupport", "BelayCore"]),
        .target(name: "BelayProviders", dependencies: ["BelaySupport", "BelayCore"]),
        .target(name: "BelayHookBridge", dependencies: ["BelaySupport", "BelayCore"]),
        .target(name: "BelayTipJar", dependencies: ["BelaySupport"]),

        .testTarget(name: "BelaySupportTests", dependencies: ["BelaySupport"]),
        .testTarget(name: "BelayCoreTests", dependencies: ["BelayCore"]),
        .testTarget(name: "BelayPowerTests", dependencies: ["BelayPower"]),
        .testTarget(name: "BelaySettingsTests", dependencies: ["BelaySettings"]),
        .testTarget(
            name: "BelayProvidersTests",
            dependencies: ["BelayProviders"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "BelayHookBridgeTests", dependencies: ["BelayHookBridge"]),
        .testTarget(name: "BelayTipJarTests", dependencies: ["BelayTipJar"]),

        // Spans provider → bus → coordinator → power backend. docs/08 asks for
        // the hold/release timeline to be asserted end to end, and no
        // single-module test target can import all four.
        .testTarget(
            name: "BelayIntegrationTests",
            dependencies: ["BelayProviders", "BelayCore", "BelayPower"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
