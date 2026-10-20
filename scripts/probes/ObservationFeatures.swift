// SPDX-License-Identifier: GPL-3.0-or-later
import Observation
import Synchronization

@Observable
final class ObservedNumber {
  var value = 0
}

@main
struct ObservationFeatures {
  @MainActor
  static func main() async {
    let number = ObservedNumber()
    let notificationCount = Mutex(0)
    withObservationTracking(options: [.didSet]) {
      _ = number.value
    } onChange: { event in
      precondition(event.kind == .didSet)
      precondition(event.matches(\ObservedNumber.value))
      notificationCount.withLock { $0 += 1 }
    }
    number.value = 1
    precondition(notificationCount.withLock { $0 } == 1)
    number.value = 2
    precondition(notificationCount.withLock { $0 } == 1)

    let (stream, continuation) = AsyncStream<Int>.makeStream()
    let token = withContinuousObservation(options: [.didSet]) { _ in
      // Reading on every callback establishes the next observation dependency.
      continuation.yield(number.value)
    }
    var iterator = stream.makeAsyncIterator()
    let initial = await iterator.next()
    precondition(initial == 2)
    number.value = 3
    let updated = await iterator.next()
    precondition(updated == 3)
    token.cancel()
    continuation.finish()
    print("PASS: @Observable macro, didSet tracking, key paths, continuous delivery, token consumption")
  }
}
