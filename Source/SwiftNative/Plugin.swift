// Copyright (C) 2026 EmacsSwiftModule contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This file is part of EmacsSwiftModule, distributed without any warranty.
// See LICENSE for the GNU General Public License, version 3 or later.

internal import EmacsModule
internal import PluginSupport
internal import Synchronization

/// A native Swift plugin. The factory build plugin supplies the Emacs entry point.
public protocol Plugin {
  /// A Lisp symbol prefix used for the feature and lifecycle commands.
  static var name: String { get }
  static var commands: [Command] { get }
}

public enum PluginError: Error, Sendable, CustomStringConvertible {
  case message(String)
  case closed
  case cancelled
  case integerOverflow
  case invalidDeclaration

  public var description: String {
    switch self {
    case .message(let message): message
    case .closed: "The Swift plugin has been shut down."
    case .cancelled: "The Swift task was cancelled."
    case .integerOverflow: "The result does not fit in a Swift Int."
    case .invalidDeclaration: "Invalid or duplicate Swift plugin command declaration."
    }
  }
}

/// A Lisp command implemented using native, Sendable Swift values.
///
/// Async string commands take three Lisp arguments: a string, a success function,
/// and a failure function. They return an integer task identifier. Completion
/// functions receive one string and run only when Emacs calls its process filter.
public struct Command: Sendable {
  let name: String
  let documentation: String
  let implementation: Implementation

  enum Implementation: Sendable {
    case string(@Sendable (String) throws -> String)
    case integers(@Sendable (Int, Int) throws -> Int)
    case asyncString(@Sendable (String) async throws -> String)
  }

  public init(
    _ name: String, documentation: String = "",
    _ implementation: @escaping @Sendable (String) throws -> String
  ) {
    self.name = name
    self.documentation = documentation
    self.implementation = .string(implementation)
  }

  public init(
    _ name: String, documentation: String = "",
    _ implementation: @escaping @Sendable (Int, Int) throws -> Int
  ) {
    self.name = name
    self.documentation = documentation
    self.implementation = .integers(implementation)
  }

  public init(
    _ name: String, documentation: String = "",
    _ implementation: @escaping @Sendable (String) async throws -> String
  ) {
    self.name = name
    self.documentation = documentation
    self.implementation = .asyncString(implementation)
  }
}

/// A completion is claimed once, even when cancellation races native completion.
/// No task captures an Environment or a callback-local Value.
private final class AsyncJob: Sendable {
  let channel: Channel
  let success: PersistentValue
  let failure: PersistentValue
  private let completed = Mutex(false)
  private let task = Mutex<Task<Void, Never>?>(nil)

  init(channel: Channel, success: PersistentValue, failure: PersistentValue) {
    self.channel = channel
    self.success = success
    self.failure = failure
  }

  func attach(_ newTask: Task<Void, Never>) {
    task.withLock { handle in
      if completed.withLock({ $0 }) { newTask.cancel() }
      else { handle = newTask }
    }
  }

  func complete(_ result: Result<String, PluginError>) {
    let claimed = completed.withLock { done in
      if done { return false }
      done = true
      return true
    }
    guard claimed else { return }
    task.withLock { $0 = nil }
    let callback: PersistentValue
    let message: String
    switch result {
    case .success(let value):
      callback = success
      message = value
    case .failure(let error):
      callback = failure
      message = error.description
    }
    Task { [channel] in
      do {
        try await channel.withEnvironment { environment in
          _ = try environment.call(
            environment.value(from: callback), arguments: [environment.make(message)])
        }
      } catch {
        // Channel shutdown settles the waiter; no Emacs call can follow it.
      }
    }
  }

  func cancel(deliverCompletion: Bool) {
    let handle = task.withLock { task in
      let handle = task
      task = nil
      return handle
    }
    if deliverCompletion {
      complete(.failure(.cancelled))
    } else {
      completed.withLock { $0 = true }
    }
    handle?.cancel()
  }
}

private final class PluginRuntime: Sendable {
  struct State: Sendable {
    var closed = false
    var nextTask = 1
    var jobs: [Int: AsyncJob] = [:]
  }

  let channel: Channel
  private let state = Mutex(State())

  init(channel: Channel) { self.channel = channel }

  func checkActive() throws {
    guard !state.withLock({ $0.closed }) else { throw PluginError.closed }
  }

  func start(
    _ operation: @escaping @Sendable (String) async throws -> String,
    input: String, success: PersistentValue, failure: PersistentValue
  ) throws -> Int {
    let job = AsyncJob(channel: channel, success: success, failure: failure)
    let identifier = try state.withLock { state in
      guard !state.closed else { throw PluginError.closed }
      guard state.nextTask < Int.max else { throw PluginError.integerOverflow }
      let identifier = state.nextTask
      state.nextTask += 1
      state.jobs[identifier] = job
      return identifier
    }
    let task = Task { [self] in
      defer { state.withLock { $0.jobs.removeValue(forKey: identifier) } }
      do {
        try Task.checkCancellation()
        let result = try await operation(input)
        try Task.checkCancellation()
        job.complete(.success(result))
      } catch is CancellationError {
        job.complete(.failure(.cancelled))
      } catch {
        job.complete(.failure(.message(String(describing: error))))
      }
    }
    job.attach(task)
    return identifier
  }

  func cancel(_ identifier: Int) -> Bool {
    guard let job = state.withLock({ $0.jobs.removeValue(forKey: identifier) }) else {
      return false
    }
    job.cancel(deliverCompletion: true)
    return true
  }

  func close() {
    let jobs = state.withLock { state in
      state.closed = true
      let jobs = Array(state.jobs.values)
      state.jobs.removeAll()
      return jobs
    }
    // Closing first prevents delivery of queued completions during shutdown.
    channel.close()
    for job in jobs { job.cancel(deliverCompletion: false) }
  }

  deinit { channel.close() }
}

/// Entry-point implementation used only by generated bootstrap code.
@_spi(ModuleEntry)
public func initializePlugin<P: Plugin>(
  _ plugin: P.Type, runtime runtimePointer: UnsafeMutableRawPointer
) -> Int32 {
  emacs_swift_link_plugin_support()
  let runtime = runtimePointer.assumingMemoryBound(to: emacs_runtime.self)
  guard runtime.pointee.size >= MemoryLayout<emacs_runtime>.size,
        let rawEnvironment = runtime.pointee.get_environment(runtime),
        let environment = try? Environment(rawEnvironment) else { return 1 }
  defer { environment.finish() }
  var owner: PluginRuntime?
  do {
    let name = P.name
    let commands = P.commands
    let reserved = [name + "-cancel-task", name + "-shutdown"]
    let names = commands.map(\.name) + reserved
    guard !name.isEmpty, !name.utf8.contains(0),
          Set(names).count == names.count,
          names.allSatisfy({ !$0.isEmpty && !$0.utf8.contains(0) }),
          commands.allSatisfy({ !$0.documentation.utf8.contains(0) }) else {
      throw PluginError.invalidDeclaration
    }
    let runtime = PluginRuntime(channel: try environment.openChannel(name: name))
    owner = runtime
    for command in commands {
      switch command.implementation {
      case .string(let implementation):
        try environment.define(
          name: command.name, arity: 1, documentation: command.documentation
        ) { environment, arguments in
          try runtime.checkActive()
          return try environment.make(implementation(environment.string(arguments[0])))
        }
      case .integers(let implementation):
        try environment.define(
          name: command.name, arity: 2, documentation: command.documentation
        ) { environment, arguments in
          try runtime.checkActive()
          let first = try environment.integer(arguments[0])
          let second = try environment.integer(arguments[1])
          guard let a = Int(exactly: first), let b = Int(exactly: second) else {
            throw PluginError.integerOverflow
          }
          return try environment.make(Int64(implementation(a, b)))
        }
      case .asyncString(let implementation):
        try environment.define(
          name: command.name, arity: 3, documentation: command.documentation
        ) { environment, arguments in
          try runtime.checkActive()
          let input = try environment.string(arguments[0])
          for callback in arguments.dropFirst() {
            guard try !environment.isNil(
              environment.call("functionp", arguments: [callback])) else {
              throw PluginError.message("Async completion arguments must be Lisp functions.")
            }
          }
          let identifier = try runtime.start(
            implementation, input: input,
            success: environment.preserve(arguments[1]),
            failure: environment.preserve(arguments[2]))
          return try environment.make(Int64(identifier))
        }
      }
    }
    try environment.define(name: reserved[0], arity: 1) { environment, arguments in
      let raw = try environment.integer(arguments[0])
      guard let identifier = Int(exactly: raw) else { throw PluginError.integerOverflow }
      return try environment.make(runtime.cancel(identifier))
    }
    try environment.define(name: reserved[1], arity: 0) { environment, _ in
      runtime.close()
      return try environment.make(false)
    }
    _ = try environment.call("provide", arguments: [environment.intern(name)])
    return 0
  } catch {
    owner?.close()
    environment.report(error)
    return 1
  }
}
