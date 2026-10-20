// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "EmacsSwiftModule",
    platforms: [.macOS("27.0")],
    products: [.library(name: "EmacsSwiftModule", targets: ["EmacsSwiftModule"])],
    targets: [
        .target(name: "EmacsSwiftModule", path: "Sources/EmacsSwiftModule"),
        .testTarget(name: "EmacsSwiftModuleTests", dependencies: ["EmacsSwiftModule"], path: "Tests/EmacsSwiftModuleTests"),
    ],
    swiftLanguageModes: [.v6]
)
