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
        // R1 (corrected-E): tree-core is now the family home — it hosts Tree.Protocol, the
        // shared arena (TreeStorage over Shared<Node, Column.Generational<Node>>), the shared
        // defaults, and the canonical dynamic Tree. So the arena/queue/stack/buffer backings
        // (previously in the per-variant packages) return here.
        .package(url: "https://github.com/swift-primitives/swift-index-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-column-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-shared-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-storage-arena-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-store-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-ring-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-queue-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-stack-primitives.git", branch: "main"),
        // R1 W4: the read-only fluent accessor views (Tree.forEach / Tree.child) are built on
        // `Property<Tag, Base>.Borrow` — the [PRP-001]-canonical mechanism for ~Copyable fluent
        // accessors (bespoke borrowing views wall on 6.3.2; probe-confirmed). Seat-ratified dep.
        .package(url: "https://github.com/swift-primitives/swift-property-primitives.git", branch: "main"),
    ],
    targets: [
        // MARK: - Core (the family home: Tree.Protocol + TreeStorage arena + defaults +
        //         canonical dynamic Tree; plus the legacy `Tree` namespace shell until W4
        //         dissolves it)
        .target(
            name: "Tree Primitives Core",
            dependencies: [
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "Column Primitives", package: "swift-column-primitives"),
                .product(name: "Shared Primitive", package: "swift-shared-primitives"),
                .product(name: "Storage Generational Primitives", package: "swift-storage-arena-primitives"),
                .product(name: "Store Primitive", package: "swift-store-primitives"),
                .product(name: "Buffer Ring Primitive", package: "swift-buffer-ring-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Property Primitives", package: "swift-property-primitives"),
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
