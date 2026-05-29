// swift-tools-version: 6.3.1

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
        // MARK: - Core (the `Tree` namespace shell: Tree, Tree.Index, Tree.Position)
        .library(
            name: "Tree Primitives Core",
            targets: ["Tree Primitives Core"]
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
        // Shell deps pruned 5 → 1: the namespace shell only needs Index
        // (Tree.Index typealias + Tree.Position's Index<Self>/Ordinal). The
        // arena/queue/stack/buffer backings moved out with the disciplines to
        // swift-tree-n-primitives, swift-tree-unbounded-primitives,
        // swift-tree-keyed-primitives.
        .package(url: "https://github.com/swift-primitives/swift-index-primitives.git", branch: "main"),
    ],
    targets: [
        // MARK: - Core (namespace shell)
        .target(
            name: "Tree Primitives Core",
            dependencies: [
                .product(name: "Index Primitives", package: "swift-index-primitives"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Tree Primitives",
            dependencies: [
                "Tree Primitives Core",
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
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = [
        .enableExperimentalFeature("RawLayout"),
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
