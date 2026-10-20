// Copyright (C) 2026 EmacsSwiftModule contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// A native Swift value that can cross a plugin command boundary.
public indirect enum PluginValue: Sendable, Equatable {
    case null
    case boolean(Bool)
    case integer(Int)
    case floatingPoint(Double)
    case text(String)
    case array([PluginValue])
}

/// Conversion between a Swift type and a plugin value.
public protocol PluginValueConvertible: Sendable {
    init(pluginValue: PluginValue) throws
    var pluginValue: PluginValue { get }
}

public enum CommandError: Error, Sendable, Equatable {
    case invalidName(String)
    case duplicateName(String)
    case unknownCommand(String)
    case incorrectArgumentCount(expected: Int, actual: Int)
    case incorrectValueType(expected: String)
}

extension String: PluginValueConvertible {
    public init(pluginValue: PluginValue) throws {
        guard case .text(let value) = pluginValue else {
            throw CommandError.incorrectValueType(expected: "String")
        }
        self = value
    }

    public var pluginValue: PluginValue { .text(self) }
}

extension Int: PluginValueConvertible {
    public init(pluginValue: PluginValue) throws {
        guard case .integer(let value) = pluginValue else {
            throw CommandError.incorrectValueType(expected: "Int")
        }
        self = value
    }

    public var pluginValue: PluginValue { .integer(self) }
}

extension Bool: PluginValueConvertible {
    public init(pluginValue: PluginValue) throws {
        guard case .boolean(let value) = pluginValue else {
            throw CommandError.incorrectValueType(expected: "Bool")
        }
        self = value
    }

    public var pluginValue: PluginValue { .boolean(self) }
}

extension Double: PluginValueConvertible {
    public init(pluginValue: PluginValue) throws {
        guard case .floatingPoint(let value) = pluginValue else {
            throw CommandError.incorrectValueType(expected: "Double")
        }
        self = value
    }

    public var pluginValue: PluginValue { .floatingPoint(self) }
}

extension Optional: PluginValueConvertible where Wrapped: PluginValueConvertible {
    public init(pluginValue: PluginValue) throws {
        if case .null = pluginValue { self = nil }
        else { self = try Wrapped(pluginValue: pluginValue) }
    }

    public var pluginValue: PluginValue { self?.pluginValue ?? .null }
}

extension Array: PluginValueConvertible where Element: PluginValueConvertible {
    public init(pluginValue: PluginValue) throws {
        guard case .array(let values) = pluginValue else {
            throw CommandError.incorrectValueType(expected: "Array")
        }
        self = try values.map(Element.init(pluginValue:))
    }

    public var pluginValue: PluginValue { .array(map(\.pluginValue)) }
}

/// A typed synchronous Swift command. Argument count is inferred from its closure.
public struct Command: Sendable {
    public let name: String
    public let documentation: String
    public let argumentCount: Int
    private let call: @Sendable ([PluginValue]) throws -> PluginValue

    public init<each Input: PluginValueConvertible, Output: PluginValueConvertible>(
        _ name: String,
        documentation: String = "",
        run: @escaping @Sendable (repeat each Input) throws -> Output
    ) {
        self.name = name
        self.documentation = documentation
        var count = 0
        for _ in repeat (each Input).self { count += 1 }
        argumentCount = count
        call = { arguments in
            var index = 0
            func next<T: PluginValueConvertible>(_ type: T.Type) throws -> T {
                defer { index += 1 }
                return try T(pluginValue: arguments[index])
            }
            return try run(repeat next((each Input).self)).pluginValue
        }
    }

    public func invoke(with arguments: [PluginValue]) throws -> PluginValue {
        guard arguments.count == argumentCount else {
            throw CommandError.incorrectArgumentCount(expected: argumentCount, actual: arguments.count)
        }
        return try call(arguments)
    }
}

public protocol Plugin {
    static var commands: [Command] { get }
}

/// Validates and dispatches the commands declared by a plugin.
public struct CommandRegistry: Sendable {
    private let commands: [String: Command]

    public init<P: Plugin>(_ plugin: P.Type) throws {
        var registered: [String: Command] = [:]
        for command in plugin.commands {
            guard !command.name.isEmpty,
                  !command.name.utf8.contains(0),
                  !command.documentation.utf8.contains(0) else {
                throw CommandError.invalidName(command.name)
            }
            guard registered.updateValue(command, forKey: command.name) == nil else {
                throw CommandError.duplicateName(command.name)
            }
        }
        commands = registered
    }

    public func invoke(_ name: String, with arguments: [PluginValue]) throws -> PluginValue {
        guard let command = commands[name] else { throw CommandError.unknownCommand(name) }
        return try command.invoke(with: arguments)
    }
}
