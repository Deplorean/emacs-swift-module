// SPDX-License-Identifier: GPL-3.0-or-later
//
// This file is part of EmacsSwiftModule.
// EmacsSwiftModule is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See <https://www.gnu.org/licenses/>.

internal import Darwin
internal import Foundation
internal import Synchronization

/// A failure to deliver work through an Emacs pipe process.
enum ChannelError: Error, Sendable {
  case closed
  case pipeFailure(Int32)
}

/// A thread-safe way to request a new, synchronous callback from Emacs.
///
/// Only the pipe descriptor and native Swift work cross concurrency boundaries.
/// Environments and temporary Lisp values remain inside an Emacs callback.
final class Channel: Sendable {
  let name: String
  private let core: ChannelCore

  fileprivate init(name: String, core: ChannelCore) {
    self.name = name
    self.core = core
  }

  var isClosed: Bool { core.isClosed }

  /// Stop accepting work and fail every request that has not started.
  ///
  /// A callback that has already started is synchronous and runs to completion.
  /// Closing the write descriptor also allows Emacs to retire its pipe process.
  func close() {
    core.close()
  }

  deinit {
    core.close()
  }

  /// Wait for Emacs to run `operation` inside a fresh callback.
  ///
  /// Cancellation prevents a queued operation from starting. It cannot undo
  /// side effects of an operation that has already started.
  func withEnvironment<Result: Sendable>(
    _ operation: @escaping @Sendable (Environment) throws -> Result
  ) async throws -> Result {
    let request = ChannelRequest(operation: operation)
    let identifier = UUID()
    let core = core
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        request.install(continuation)
        core.enqueue(
          ChannelJob(
            identifier: identifier,
            isPending: { request.isPending },
            claim: { request.claim() },
            run: { environment in request.run(in: environment) },
            reject: { error in request.finish(.failure(error)) }
          )
        )
      }
    } onCancel: {
      core.cancel(identifier)
      request.finish(.failure(CancellationError()))
    }
  }
}

private struct ChannelJob: Sendable {
  let identifier: UUID
  let isPending: @Sendable () -> Bool
  let claim: @Sendable () -> Bool
  let run: @Sendable (Environment) -> Void
  let reject: @Sendable (any Error) -> Void
}

private struct ChannelRequestState<Result: Sendable>: Sendable {
  var continuation: CheckedContinuation<Result, any Error>?
  var outcome: Swift.Result<Result, any Error>?
  var started = false
  var finished = false
}

/// The continuation and cancellation handler may arrive in either order.
/// Their single completion point prevents double resumes in every ordering.
private final class ChannelRequest<Result: Sendable>: Sendable {
  private let operation: @Sendable (Environment) throws -> Result
  private let state = Mutex(ChannelRequestState<Result>())

  init(operation: @escaping @Sendable (Environment) throws -> Result) {
    self.operation = operation
  }

  var isPending: Bool {
    state.withLock { !$0.finished && !$0.started }
  }

  func install(_ continuation: CheckedContinuation<Result, any Error>) {
    let completed: Swift.Result<Result, any Error>? = state.withLock { state in
      if state.finished {
        let outcome = state.outcome
        state.outcome = nil
        return outcome
      }
      state.continuation = continuation
      return nil
    }
    if let completed {
      continuation.resume(with: completed)
    }
  }

  func claim() -> Bool {
    state.withLock { state in
      guard !state.finished, !state.started else { return false }
      state.started = true
      return true
    }
  }

  func run(in environment: Environment) {
    do {
      finish(.success(try operation(environment)))
    } catch {
      finish(.failure(error))
    }
  }

  func finish(_ outcome: Swift.Result<Result, any Error>) {
    let continuation: CheckedContinuation<Result, any Error>? =
      state.withLock { state in
        guard !state.finished else { return nil }
        state.finished = true
        if let continuation = state.continuation {
          state.continuation = nil
          return continuation
        }
        state.outcome = outcome
        return nil
      }
    continuation?.resume(with: outcome)
  }
}

private struct ChannelState: Sendable {
  var descriptor: Int32?
  var closed = false
  var pending: [UUID: ChannelJob] = [:]
  var order: [UUID] = []
  var next = 0

  mutating func removeNext() -> ChannelJob? {
    while next < order.count {
      let identifier = order[next]
      next += 1
      if let job = pending.removeValue(forKey: identifier) {
        if pending.isEmpty {
          order.removeAll(keepingCapacity: true)
          next = 0
        }
        return job
      }
    }
    order.removeAll(keepingCapacity: true)
    next = 0
    return nil
  }

  mutating func terminate() -> [ChannelJob] {
    closed = true
    if let descriptor {
      // All writers hold this same mutex, so close cannot race a write or
      // accidentally close a subsequently reused descriptor.
      _ = Darwin.close(descriptor)
      self.descriptor = nil
    }
    let abandoned = Array(pending.values)
    pending.removeAll()
    order.removeAll()
    next = 0
    return abandoned
  }
}

/// Captured by Lisp's filter instead of Channel, so its capture does not keep
/// the owner alive and prevent Channel.deinit from closing the descriptor.
private final class ChannelCore: Sendable {
  private let state = Mutex(ChannelState())

  var isClosed: Bool { state.withLock { $0.closed } }

  func install(_ descriptor: Int32) throws {
    guard descriptor >= 0 else { throw ChannelError.pipeFailure(EBADF) }
    let flags = Darwin.fcntl(descriptor, F_GETFL)
    guard flags >= 0,
      Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0,
      Darwin.fcntl(descriptor, F_SETNOSIGPIPE, 1) >= 0
    else {
      let code = errno
      _ = Darwin.close(descriptor)
      throw ChannelError.pipeFailure(code)
    }
    let accepted = state.withLock { state in
      guard !state.closed, state.descriptor == nil else { return false }
      state.descriptor = descriptor
      return true
    }
    guard accepted else {
      _ = Darwin.close(descriptor)
      throw ChannelError.closed
    }
  }

  func enqueue(_ job: ChannelJob) {
    let failure: ([ChannelJob], ChannelError)? = state.withLock { state in
      guard !state.closed, let descriptor = state.descriptor else {
        return ([job], .closed)
      }
      guard job.isPending() else { return nil }
      state.pending[job.identifier] = job
      state.order.append(job.identifier)
      var byte: UInt8 = 1
      while true {
        let written = Darwin.write(descriptor, &byte, 1)
        if written == 1 { return nil }
        let code = errno
        if written < 0, code == EINTR { continue }
        if written < 0, code == EAGAIN || code == EWOULDBLOCK {
          // A full pipe already contains a wakeup for the pending queue.
          return nil
        }
        return (state.terminate(), .pipeFailure(written == 0 ? EIO : code))
      }
    }
    if let (abandoned, error) = failure {
      // Resume continuations outside the queue lock.
      for job in abandoned { job.reject(error) }
    }
  }

  func cancel(_ identifier: UUID) {
    state.withLock { state in
      state.pending.removeValue(forKey: identifier)
      if state.pending.isEmpty {
        state.order.removeAll(keepingCapacity: true)
        state.next = 0
      }
    }
  }

  func close() {
    let abandoned = state.withLock { $0.terminate() }
    for job in abandoned { job.reject(ChannelError.closed) }
  }

  func drain(in environment: Environment) {
    // Bound one filter invocation to the work present when it began. Newly
    // queued work has its own wakeup, so producers cannot monopolize Emacs.
    let budget = state.withLock { $0.pending.count }
    for _ in 0..<budget {
      let job = state.withLock { state -> ChannelJob? in
        guard !state.closed else { return nil }
        // Claim under the queue lock: once close can no longer reject a job,
        // that job has formally started.
        while let candidate = state.removeNext() {
          if candidate.claim() { return candidate }
        }
        return nil
      }
      guard let job else { return }
      job.run(environment)
    }
  }
}

extension Environment {
  /// Create a pipe process while Emacs has granted an active environment.
  func openChannel(name: String) throws -> Channel {
    let core = ChannelCore()
    let filter = try define(
      name: nil, arity: 2,
      documentation: "Run pending native Swift callbacks."
    ) { environment, _ in
      core.drain(in: environment)
      return try environment.make(false)
    }
    let sentinel = try define(
      name: nil, arity: 2,
      documentation: "Cancel pending native Swift callbacks when a pipe closes."
    ) { environment, arguments in
      let alive = try environment.call(
        "process-live-p", arguments: [arguments[0]]
      )
      if try environment.isNil(alive) { core.close() }
      return try environment.make(false)
    }
    let process = try call(
      "make-pipe-process",
      arguments: [
        intern(":name"), make(name),
        intern(":buffer"), make(false),
        intern(":noquery"), make(true),
        intern(":coding"), intern("binary"),
        intern(":filter"), filter,
        intern(":sentinel"), sentinel,
      ]
    )
    do {
      try core.install(openChannelDescriptor(process: process))
      return Channel(name: name, core: core)
    } catch {
      core.close()
      _ = try? call("delete-process", arguments: [process])
      throw error
    }
  }
}
