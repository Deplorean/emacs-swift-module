// Copyright (C) 2026 EmacsSwiftModule contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This file is part of EmacsSwiftModule, distributed without any warranty.
// See LICENSE for the GNU General Public License, version 3 or later.

internal import Darwin
internal import EmacsModule
internal import Synchronization

enum BridgeError: Error, Sendable {
  case expiredEnvironment
  case wrongThread
  case foreignValue
  case lispFailure
  case invalidString
  case invalidArguments
  case unsupportedRuntime
}

/// This token belongs to one synchronous entry from Emacs.
/// Check the immutable thread identifier before reading the mutable validity bit.
final class CallbackScope {
  let thread = pthread_self()
  private var active = true

  func validate() throws {
    guard pthread_equal(thread, pthread_self()) != 0 else { throw BridgeError.wrongThread }
    guard active else { throw BridgeError.expiredEnvironment }
  }

  func invalidate() {
    precondition(pthread_equal(thread, pthread_self()) != 0)
    active = false
  }
}

final class Value {
  let raw: emacs_value?
  let scope: CallbackScope

  init(_ raw: emacs_value?, scope: CallbackScope) {
    self.raw = raw
    self.scope = scope
  }
}

/// Only global references cross threads. Store the opaque address without
/// dereferencing it; every Emacs operation still requires a live Environment.
final class PersistentValue: Sendable {
  let address: UInt
  private static let pending = Mutex<[UInt]>([])

  init(_ raw: emacs_value) {
    address = UInt(bitPattern: raw)
  }

  deinit {
    Self.pending.withLock { $0.append(address) }
  }

  static func drain(in environment: Environment) {
    guard (try? environment.validate()) != nil,
          environment.raw.pointee.non_local_exit_check(environment.raw)
            == emacs_funcall_exit_return else { return }
    let addresses = pending.withLock { values in
      let result = values
      values.removeAll(keepingCapacity: true)
      return result
    }
    for address in addresses {
      environment.raw.pointee.free_global_ref(
        environment.raw, emacs_value(bitPattern: address))
    }
  }
}

final class FunctionBox {
  let body: @Sendable (Environment, [Value]) throws -> Value
  let arity: Int

  init(arity: Int, body: @escaping @Sendable (Environment, [Value]) throws -> Value) {
    self.arity = arity
    self.body = body
  }
}

/// Intentionally internal and non-Sendable: plugin authors only receive native
/// Swift values. A fresh instance is created for every C callback.
final class Environment {
  let raw: UnsafeMutablePointer<emacs_env>
  let scope = CallbackScope()

  init(_ raw: UnsafeMutablePointer<emacs_env>) throws {
    // Function finalizers and open_channel require Emacs 28 or newer.
    guard raw.pointee.size >= MemoryLayout<emacs_env_28>.size else {
      throw BridgeError.unsupportedRuntime
    }
    self.raw = raw
    PersistentValue.drain(in: self)
  }

  func validate() throws { try scope.validate() }

  func finish() {
    PersistentValue.drain(in: self)
    scope.invalidate()
  }

  private func checked(_ value: emacs_value?) throws -> Value {
    try check()
    return Value(value, scope: scope)
  }

  func check() throws {
    try validate()
    guard raw.pointee.non_local_exit_check(raw) == emacs_funcall_exit_return else {
      throw BridgeError.lispFailure
    }
  }

  func unwrap(_ value: Value) throws -> emacs_value? {
    try validate()
    guard value.scope === scope else { throw BridgeError.foreignValue }
    try value.scope.validate()
    return value.raw
  }

  func intern(_ name: String) throws -> Value {
    try check()
    guard !name.utf8.contains(0) else { throw BridgeError.invalidString }
    return try checked(raw.pointee.intern(raw, name))
  }

  func make(_ value: String) throws -> Value {
    try check()
    return try value.utf8CString.withUnsafeBufferPointer {
      try checked(raw.pointee.make_string(raw, $0.baseAddress, $0.count - 1))
    }
  }

  func make(_ value: Int64) throws -> Value {
    try check()
    return try checked(raw.pointee.make_integer(raw, value))
  }

  func make(_ value: Bool) throws -> Value {
    try intern(value ? "t" : "nil")
  }

  func integer(_ value: Value) throws -> Int64 {
    let argument = try unwrap(value)
    try check()
    let result = raw.pointee.extract_integer(raw, argument)
    try check()
    return result
  }

  func isNil(_ value: Value) throws -> Bool {
    let argument = try unwrap(value)
    try check()
    let result = !raw.pointee.is_not_nil(raw, argument)
    try check()
    return result
  }

  func string(_ value: Value) throws -> String {
    let argument = try unwrap(value)
    try check()
    var length = 0
    _ = raw.pointee.copy_string_contents(raw, argument, nil, &length)
    try check()
    guard length > 0 else { throw BridgeError.invalidString }
    var bytes = [CChar](repeating: 0, count: length)
    let copied = raw.pointee.copy_string_contents(raw, argument, &bytes, &length)
    try check()
    guard copied, length > 0, length <= bytes.count else { throw BridgeError.invalidString }
    let utf8 = bytes.prefix(length - 1).map { UInt8(bitPattern: $0) }
    guard let result = String(validating: utf8, as: UTF8.self) else {
      throw BridgeError.invalidString
    }
    return result
  }

  func call(_ name: String, arguments: [Value] = []) throws -> Value {
    try call(intern(name), arguments: arguments)
  }

  func call(_ function: Value, arguments: [Value] = []) throws -> Value {
    let functionRaw = try unwrap(function)
    var args = try arguments.map(unwrap)
    try check()
    return try args.withUnsafeMutableBufferPointer {
      try checked(raw.pointee.funcall(raw, functionRaw, $0.count, $0.baseAddress))
    }
  }

  func preserve(_ value: Value) throws -> PersistentValue {
    let argument = try unwrap(value)
    try check()
    let reference = raw.pointee.make_global_ref(raw, argument)
    try check()
    guard let reference else { throw BridgeError.lispFailure }
    return PersistentValue(reference)
  }

  func value(from reference: PersistentValue) throws -> Value {
    try check()
    // The wrapper retains the global reference until this callback ends by
    // creating a local value through identity, rather than borrowing its owner.
    return try withExtendedLifetime(reference) {
      let global = Value(emacs_value(bitPattern: reference.address), scope: scope)
      return try call("identity", arguments: [global])
    }
  }

  func openChannelDescriptor(process: Value) throws -> Int32 {
    let argument = try unwrap(process)
    try check()
    let descriptor = raw.pointee.open_channel(raw, argument)
    try check()
    guard descriptor >= 0 else { throw BridgeError.lispFailure }
    return descriptor
  }

  @discardableResult
  func define(
    name: String? = nil, arity: Int, documentation: String = "",
    body: @escaping @Sendable (Environment, [Value]) throws -> Value
  ) throws -> Value {
    try check()
    guard arity >= 0, !documentation.utf8.contains(0) else {
      throw BridgeError.invalidArguments
    }
    let box = FunctionBox(arity: arity, body: body)
    let opaque = Unmanaged.passRetained(box).toOpaque()
    let function = raw.pointee.make_function(
      raw, arity, arity,
      { rawEnvironment, count, arguments, context in
        guard let rawEnvironment, let context,
              let environment = try? Environment(rawEnvironment) else { return nil }
        defer { environment.finish() }
        // Acquire the fallback before user code may establish a non-local exit.
        let fallback = try? environment.intern("nil")
        do {
          let implementation = Unmanaged<FunctionBox>.fromOpaque(context).takeUnretainedValue()
          guard count == implementation.arity, count == 0 || arguments != nil else {
            throw BridgeError.invalidArguments
          }
          let values = UnsafeBufferPointer(start: arguments, count: count).map {
            Value($0, scope: environment.scope)
          }
          return try environment.unwrap(implementation.body(environment, values))
        } catch {
          environment.report(error)
          return fallback?.raw
        }
      }, documentation, opaque)
    do { try check() } catch {
      Unmanaged<FunctionBox>.fromOpaque(opaque).release()
      throw error
    }
    raw.pointee.set_function_finalizer(raw, function) { pointer in
      if let pointer { Unmanaged<FunctionBox>.fromOpaque(pointer).release() }
    }
    // If finalizer registration fails, ownership is deliberately retained: Emacs
    // may still hold the function. Releasing would leave a dangling callback.
    try check()
    let value = Value(function, scope: scope)
    if let name { _ = try call("fset", arguments: [intern(name), value]) }
    return value
  }

  func report(_ error: any Error) {
    guard (try? validate()) != nil,
          raw.pointee.non_local_exit_check(raw) == emacs_funcall_exit_return else { return }
    do {
      let symbol = try intern("error")
      let data = try call("list", arguments: [make(String(describing: error))])
      raw.pointee.non_local_exit_signal(raw, symbol.raw, data.raw)
    } catch {
      // Preserve whatever Emacs signaled while constructing the error.
    }
  }
}
