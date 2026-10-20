// SPDX-License-Identifier: GPL-3.0-or-later
// Part of EmacsSwiftModule. See the repository's LICENSE.

import EmacsSwiftModule

private enum GreetingError: Error, CustomStringConvertible {
  case emptyName
  case integerOverflow

  var description: String {
    switch self {
    case .emptyName:
      return "A name must not be empty."
    case .integerOverflow:
      return "The sum does not fit in a Swift Int."
    }
  }
}

private func greeting(for name: String) throws -> String {
  guard !name.isEmpty else { throw GreetingError.emptyName }
  return "Hello, \(name)!"
}

struct HelloPlugin: Plugin {
  static let name = "hello-plugin"

  static let commands: [Command] = [
    Command("swift-hello", documentation: "Greet NAME using a Swift String.") {
      (name: String) throws -> String in
      try greeting(for: name)
    },
    Command("swift-add", documentation: "Add two Swift Int values, checking for overflow.") {
      (a: Int, b: Int) throws -> Int in
      let (sum, overflow) = a.addingReportingOverflow(b)
      guard !overflow else { throw GreetingError.integerOverflow }
      return sum
    },
    Command(
      "swift-hello-later",
      documentation: """
      Greet NAME after a short asynchronous delay.
      Pass success and failure callbacks after NAME. Return a task identifier.
      """
    ) {
      (name: String) async throws -> String in
      try await Task.sleep(for: .milliseconds(100))
      return try greeting(for: name)
    }
  ]
}

func createPlugin() -> some Plugin {
  HelloPlugin()
}
