// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DSHDesktop",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DSHDesktop",
            path: "Sources/DSHDesktop"
        )
    ]
)
