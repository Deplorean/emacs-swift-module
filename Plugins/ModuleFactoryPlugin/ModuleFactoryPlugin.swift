// SPDX-License-Identifier: GPL-3.0-or-later
import PackagePlugin
import Foundation

@main
struct ModuleFactoryPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let output = context.pluginWorkDirectoryURL.appending(path: "ModuleInitializer.swift")
    return [
      .buildCommand(
        displayName: "Generate Emacs module entry point",
        executable: try context.tool(named: "ModuleInitializerInjector").url,
        arguments: [output.path],
        outputFiles: [output]
      )
    ]
  }
}
