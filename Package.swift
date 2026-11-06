// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipPress",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClipPress", path: "Sources/ClipPress")
    ]
)
