<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
Reference for Swift plugin authors: typed command declarations and values.

# Commands

Conform to `Plugin` and return a list of `Command` values. A command infers its
argument count and conversion types from the Swift closure. Commands currently
accept synchronous throwing closures and native `String`, `Int`, `Bool`,
`Double`, optional and array values. Conversion failures throw `CommandError`.

`CommandRegistry` validates unique names and dispatches native values. The
registry is the contract the internal Emacs adapter will call; ordinary plugin
authors do not need the adapter or `PluginValue`.

```swift
struct Example: Plugin {
    static let commands = [
        Command("hello") { (name: String) -> String in "Hello, \(name)!" },
        Command("add") { (a: Int, b: Int) -> Int in a + b },
    ]
}
```

No asynchronous command or editor operation is exposed by this slice. Their
lifecycle and isolation contracts are tracked by issue #3 before publication.
