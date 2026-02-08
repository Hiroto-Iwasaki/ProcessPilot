// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProcessPilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ProcessPilot", targets: ["ProcessPilot"]),
        .executable(name: "ProcessPilotPrivilegedHelper", targets: ["ProcessPilotPrivilegedHelper"])
    ],
    targets: [
        .target(
            name: "ProcessPilotCommon",
            path: "ProcessPilotCommon"
        ),
        .executableTarget(
            name: "ProcessPilot",
            dependencies: ["ProcessPilotCommon"],
            path: "ProcessPilot",
            exclude: [
                "Assets.xcassets",
                "ProcessPilot.entitlements"
            ]
        ),
        .executableTarget(
            name: "ProcessPilotPrivilegedHelper",
            dependencies: ["ProcessPilotCommon"],
            path: "PrivilegedHelper",
            exclude: [
                "Info.plist",
                "Launchd.plist",
                "Info.plist.template",
                "Launchd.plist.template"
            ]
        ),
        .testTarget(
            name: "ProcessPilotTests",
            dependencies: ["ProcessPilot"],
            path: "Tests/ProcessPilotTests"
        )
    ]
)
