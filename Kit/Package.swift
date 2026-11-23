// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShazamScrobblerKit",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ScrobbleCore", targets: ["ScrobbleCore"]),
        .library(name: "ShazamLibrary", targets: ["ShazamLibrary"]),
        .library(name: "ScrobbleClients", targets: ["ScrobbleClients"]),
    ],
    targets: [
        .target(name: "SQLiteLite", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "ScrobbleCore", dependencies: ["SQLiteLite"]),
        .target(name: "ShazamLibrary", dependencies: ["ScrobbleCore", "SQLiteLite"]),
        .target(name: "ScrobbleClients", dependencies: ["ScrobbleCore"]),
        // Test doubles and fixtures shared by unit and integration tests. Not a product; never linked by the app.
        .target(name: "TestSupport", dependencies: ["ScrobbleCore", "SQLiteLite"]),
        .testTarget(name: "SQLiteLiteTests", dependencies: ["SQLiteLite"]),
        .testTarget(name: "ScrobbleCoreTests", dependencies: ["ScrobbleCore", "SQLiteLite", "TestSupport"]),
        .testTarget(name: "ShazamLibraryTests", dependencies: ["ShazamLibrary", "SQLiteLite", "TestSupport"]),
        .testTarget(name: "ScrobbleClientsTests", dependencies: ["ScrobbleClients"]),
        .testTarget(name: "IntegrationTests", dependencies: ["ScrobbleCore", "ShazamLibrary", "TestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
