// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Swifotine",
    platforms: [
        .macOS(.v14)  // Target latest-only macOS per requirements
    ],
    products: [
        .executable(
            name: "Swifotine",
            targets: ["Swifotine"]
        )
    ],
    dependencies: [
        // Dependencies can be added here
    ],
    targets: [
        .executableTarget(
            name: "Swifotine",
            dependencies: [],
            path: ".",
            sources: [
                "App",
                "Core",
                "Views",
            ]
        )
    ]
)
