// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Taskit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Taskit", targets: ["Taskit"]),
        .library(name: "TaskitCore", targets: ["TaskitCore"])
    ],
    targets: [
        .target(
            name: "TaskitCore",
            path: "Sources/TaskitCore"
        ),
        .executableTarget(
            name: "Taskit",
            dependencies: ["TaskitCore"],
            path: "Sources/Taskit",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "TaskitTests",
            dependencies: ["TaskitCore"],
            path: "Tests/TaskitTests"
        )
    ]
)
