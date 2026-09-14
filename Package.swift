// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MermaidViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MermaidViewer",
            path: "MermaidViewer"
        )
    ]
)