// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpacePill",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpacePill", targets: ["SpacePill"]),
        .executable(name: "SpacePillCLI", targets: ["SpacePillCLI"])
    ],
    dependencies: [
    ],
    targets: [
        // Pure logic with no AppKit, SwiftUI or SkyLight dependency, so it can
        // be unit tested without a GUI session or private frameworks. Keep it
        // that way: anything that needs a window or a CGS connection belongs in
        // the app target.
        .target(
            name: "SpacePillCore",
            path: "SpacePillCore"
        ),
        .testTarget(
            name: "SpacePillCoreTests",
            dependencies: ["SpacePillCore"],
            path: "SpacePillCoreTests"
        ),
        .executableTarget(
            name: "SpacePill",
            dependencies: [
                "SpacePillCore"
            ],
            path: "SpacePill",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-Xlinker", "-framework", "-Xlinker", "SkyLight"])
            ]
        ),
        // The `spacepill` CLI. Deliberately links nothing private and shares no
        // code with the app: it is a socket client, so it needs no Accessibility
        // grant of its own and cannot be broken by a SkyLight API change.
        //
        // Named SpacePillCLI, not `spacepill`, because macOS filesystems are
        // case-insensitive by default: a target called `spacepill` shares its
        // `.build/<arch>/<config>/spacepill.build` directory and its output
        // binary with `SpacePill`, and SwiftPM silently compiles the app's
        // sources into it. `bin/start.sh` and `bin/package.sh` copy the product
        // into the bundle under the name users actually type.
        .executableTarget(
            name: "SpacePillCLI",
            path: "SpacePillCLI"
        )
    ]
)
