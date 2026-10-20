// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
  name: "EmacsSwiftModule",
  platforms: [.macOS("27.0")],
  products: [
    .library(name: "EmacsSwiftModule", targets: ["EmacsSwiftModule"]),
    .plugin(name: "ModuleFactoryPlugin", targets: ["ModuleFactoryPlugin"])
  ],
  targets: [
    .target(name: "EmacsModule", path: "Source/C", publicHeadersPath: "include"),
    .target(name: "PluginSupport", path: "Source/PluginSupport", publicHeadersPath: "include"),
    .target(name: "EmacsSwiftModule", dependencies: ["EmacsModule", "PluginSupport"],
            path: "Source/SwiftNative"),
    .plugin(name: "ModuleFactoryPlugin", capability: .buildTool(),
            dependencies: ["ModuleInitializerInjector"]),
    .executableTarget(name: "ModuleInitializerInjector", path: "Plugins/Generator")
  ],
  swiftLanguageModes: [.v6]
)
