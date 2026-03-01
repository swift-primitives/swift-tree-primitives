// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-tree-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        // MARK: - Core
        .library(
            name: "Tree Primitives Core",
            targets: ["Tree Primitives Core"]
        ),
        // MARK: - Variants
        .library(
            name: "Tree N Bounded Primitives",
            targets: ["Tree N Bounded Primitives"]
        ),
        .library(
            name: "Tree N Inline Primitives",
            targets: ["Tree N Inline Primitives"]
        ),
        .library(
            name: "Tree N Small Primitives",
            targets: ["Tree N Small Primitives"]
        ),
        .library(
            name: "Tree Unbounded Primitives",
            targets: ["Tree Unbounded Primitives"]
        ),
        .library(
            name: "Tree Keyed Primitives",
            targets: ["Tree Keyed Primitives"]
        ),
        // MARK: - Umbrella
        .library(
            name: "Tree Primitives",
            targets: ["Tree Primitives"]
        ),
        // MARK: - Test Support
        .library(
            name: "Tree Primitives Test Support",
            targets: ["Tree Primitives Test Support"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-stack-primitives"),
        .package(path: "../swift-queue-primitives"),
        .package(path: "../swift-array-primitives"),
        .package(path: "../swift-index-primitives"),
        .package(path: "../swift-buffer-primitives"),
        .package(path: "../swift-dictionary-primitives"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "Tree Primitives Core",
            dependencies: [
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "Buffer Arena Primitives", package: "swift-buffer-primitives"),
            ]
        ),

        // MARK: - Variants
        .target(
            name: "Tree N Bounded Primitives",
            dependencies: [
                "Tree Primitives Core",
            ]
        ),
        .target(
            name: "Tree N Inline Primitives",
            dependencies: [
                "Tree Primitives Core",
                .product(name: "Buffer Arena Inline Primitives", package: "swift-buffer-primitives"),
            ]
        ),
        .target(
            name: "Tree N Small Primitives",
            dependencies: [
                "Tree Primitives Core",
                .product(name: "Buffer Arena Inline Primitives", package: "swift-buffer-primitives"),
            ]
        ),
        .target(
            name: "Tree Unbounded Primitives",
            dependencies: [
                "Tree Primitives Core",
            ]
        ),
        .target(
            name: "Tree Keyed Primitives",
            dependencies: [
                "Tree Primitives Core",
                .product(name: "Dictionary Primitives", package: "swift-dictionary-primitives"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Tree Primitives",
            dependencies: [
                "Tree Primitives Core",
                "Tree N Bounded Primitives",
                "Tree N Inline Primitives",
                "Tree N Small Primitives",
                "Tree Unbounded Primitives",
                "Tree Keyed Primitives",
            ]
        ),

        // MARK: - Test Support
        .target(
            name: "Tree Primitives Test Support",
            dependencies: [
                "Tree Primitives",
                .product(name: "Index Primitives Test Support", package: "swift-index-primitives"),
            ],
            path: "Tests/Support"
        ),

        // MARK: - Tests
        .testTarget(
            name: "Tree Primitives Tests",
            dependencies: [
                "Tree Primitives",
                "Tree Primitives Test Support",
                .product(name: "Array Primitives", package: "swift-array-primitives"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    ]

    let package: [SwiftSetting] = [
        .enableExperimentalFeature("RawLayout"),
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
