// swift-tools-version: 5.9
import PackageDescription

// TaskitCore is Foundation-only so the queue logic builds and tests anywhere.
// The menu bar app itself is macOS-only.
var products: [Product] = [
    .library(name: "TaskitCore", targets: ["TaskitCore"])
]

var targets: [Target] = [
    .target(
        name: "TaskitCore",
        path: "Sources/TaskitCore"
    ),
    .testTarget(
        name: "TaskitTests",
        dependencies: ["TaskitCore"],
        path: "Tests/TaskitTests"
    )
]

#if os(macOS)
products.append(.executable(name: "Taskit", targets: ["Taskit"]))
targets.append(
    .executableTarget(
        name: "Taskit",
        dependencies: ["TaskitCore"],
        path: "Sources/Taskit",
        exclude: ["Resources/Info.plist"],
        resources: [
            .process("Resources/Assets.xcassets")
        ]
    )
)
#endif

let package = Package(
    name: "Taskit",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
