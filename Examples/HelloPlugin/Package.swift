// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
  name: "HelloPlugin",
  platforms: [.macOS(.v27)],
  products: [
    .library(name: "HelloPlugin", type: .dynamic, targets: ["HelloPlugin"])
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .target(
      name: "HelloPlugin",
      dependencies: [
        .product(name: "EmacsSwiftModule", package: "emacs-swift-module")
      ],
      plugins: [
        .plugin(name: "ModuleFactoryPlugin", package: "emacs-swift-module")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
