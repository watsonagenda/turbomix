// swift-tools-version: 5.9
// Package.swift — TurboMix

import PackageDescription

let package = Package(
    name: "TurboMix",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TurboMix",
            path: "Sources"
        )
    ]
)
