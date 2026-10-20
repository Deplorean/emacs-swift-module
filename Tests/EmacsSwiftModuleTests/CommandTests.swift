// SPDX-License-Identifier: GPL-3.0-or-later
import Testing
import EmacsSwiftModule

private enum ExamplePlugin: Plugin {
    static let commands = [
        Command("greet") { (name: String) -> String in "Hello, \(name)!" },
        Command("sum") { (a: Int, b: Int, c: Int) -> Int in a + b + c },
        Command("ready") { () -> Bool in true },
    ]
}

@Test func typedCommandsSupportDifferentArities() throws {
    let registry = try CommandRegistry(ExamplePlugin.self)
    #expect(try registry.invoke("ready", with: []) == .boolean(true))
    #expect(try registry.invoke("greet", with: [.text("Ada")]) == .text("Hello, Ada!"))
    #expect(try registry.invoke("sum", with: [.integer(1), .integer(2), .integer(3)]) == .integer(6))
}

@Test func conversionAndArityFailuresAreTyped() throws {
    let registry = try CommandRegistry(ExamplePlugin.self)
    #expect(throws: CommandError.incorrectArgumentCount(expected: 1, actual: 0)) {
        try registry.invoke("greet", with: [])
    }
    #expect(throws: CommandError.incorrectValueType(expected: "Int")) {
        try registry.invoke("sum", with: [.text("1"), .integer(2), .integer(3)])
    }
}

@Test func arraysAndOptionalsUseNativeConversions() throws {
    #expect(try [Int](pluginValue: .array([.integer(1), .integer(2)])) == [1, 2])
    #expect(try Optional<String>(pluginValue: .null) == nil)
}
