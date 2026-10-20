// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "EmacsSwiftModule",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "EmacsSwiftModule", targets: ["EmacsSwiftModule"]),
        .library(name: "HelloPlugin", type: .dynamic, targets: ["HelloPlugin"]),
    ],
    targets: [
        .target(name: "EmacsABI", path: "Source/C", publicHeadersPath: "include"),
        .target(name: "EmacsSwiftModule", dependencies: ["EmacsABI"], path: "Sources/EmacsSwiftModule"),
        .target(name: "HelloPlugin", dependencies: ["EmacsSwiftModule", "ModuleLicense"], path: "Examples/HelloPlugin"),
        .target(name: "ModuleLicense", path: "Sources/ModuleLicense", publicHeadersPath: "include"),
        .testTarget(name: "NativePluginTests", dependencies: ["EmacsSwiftModule"], path: "Tests/NativePluginTests"),
    ],
    swiftLanguageModes: [.v6]
)
