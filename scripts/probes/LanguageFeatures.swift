// SPDX-License-Identifier: GPL-3.0-or-later

struct OwnedNumber: ~Copyable {
  let value: Int

  borrowing func inspect() -> Int { value }
  consuming func finish() -> Int { value }
}

actor Counter {
  private var value = 0
  private var events: [String] = []

  func increment() -> Int {
    value += 1
    return value
  }

  func record(_ event: String) { events.append(event) }
  func recordedEvents() -> [String] { events }
}

func useResource(_ counter: Counter) async {
  defer {
    await counter.record("released")
  }
  await counter.record("used")
}

@main
struct LanguageFeatures {
  static func main() async {
    let owned = OwnedNumber(value: 42)
    precondition(owned.inspect() == 42)
    let finalValue = owned.finish()
    precondition(finalValue == 42)

    let counter = Counter()
    let results = await withTaskGroup(of: Int.self) { group in
      for _ in 0..<8 {
        group.addTask { await counter.increment() }
      }
      var values: [Int] = []
      for await value in group { values.append(value) }
      return values.sorted()
    }
    precondition(results == Array(1...8))
    await useResource(counter)
    let events = await counter.recordedEvents()
    precondition(events == ["used", "released"])
    print("PASS: noncopyable ownership, actor isolation, Sendable task group, async defer")
  }
}
