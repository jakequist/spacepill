// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpacePill",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpacePill", targets: ["SpacePill"])
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "SpacePill",
            dependencies: [
            ],
            path: "SpacePill",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-Xlinker", "-framework", "-Xlinker", "SkyLight"])
            ]
        )
    ]
)
