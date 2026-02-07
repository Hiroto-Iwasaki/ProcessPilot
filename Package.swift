// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProcessPilot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ProcessPilot", targets: ["ProcessPilot"])
    ],
    targets: [
        .executableTarget(
            name: "ProcessPilot",
            path: "ProcessPilot"
        )
    ]
)
