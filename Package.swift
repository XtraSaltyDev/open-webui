// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OpenWebUINative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenWebUINative", targets: ["OpenWebUINative"])
    ],
    targets: [
        .executableTarget(
            name: "OpenWebUINative"
        ),
        .testTarget(
            name: "OpenWebUINativeTests",
            dependencies: ["OpenWebUINative"]
        )
    ]
)
