// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-tree-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "Tree Primitives", targets: ["Tree Primitives"]),
        .library(name: "Tree Primitives Test Support", targets: ["Tree Primitives Test Support"]),
    ],
    dependencies: [
        .package(path: "../swift-stack-primitives"),
        .package(path: "../swift-queue-primitives"),
        .package(path: "../swift-array-primitives"),
        .package(path: "../swift-index-primitives"),
        .package(path: "../swift-input-primitives"),
        .package(path: "../swift-bit-primitives"),
        .package(path: "../swift-collection-primitives"),
        .package(path: "../swift-buffer-primitives"),
    ],
    targets: [
        .target(
            name: "Tree Primitives",
            dependencies: [
                .product(name: "Stack Primitives", package: "swift-stack-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Array Primitives", package: "swift-array-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "Input Primitives", package: "swift-input-primitives"),
                .product(name: "Bit Primitives", package: "swift-bit-primitives"),
                .product(name: "Collection Primitives", package: "swift-collection-primitives"),
                .product(name: "Buffer Arena Primitives", package: "swift-buffer-primitives"),
            ]
        ),
        .target(
            name: "Tree Primitives Test Support",
            dependencies: [
                "Tree Primitives",
                .product(name: "Index Primitives Test Support", package: "swift-index-primitives"),
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "Tree Primitives Tests",
            dependencies: [
                "Tree Primitives",
                "Tree Primitives Test Support",
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .strictMemorySafety()
    ]
}
