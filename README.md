# EmacsSwiftModule

A Swift-native framework for Emacs plugins, targeting **Swift 6.4** and
**macOS 27**. The modernization branch is under development; it is not yet a
verified release. Work and evidence are tracked in
[issue #5](https://github.com/Deplorean/emacs-swift-module/issues/5).

Declare ordinary Swift commands:

```swift
import EmacsSwiftModule

struct HelloPlugin: Plugin {
  static let name = "hello-plugin"
  static var commands: [Command] {
    [
      Command("swift-hello") { (name: String) -> String in
        "Hello, \(name)!"
      },
      Command("swift-add") { (a: Int, b: Int) -> Int in a + b }
    ]
  }
}

func createPlugin() -> some Plugin { HelloPlugin() }
```

The package build plugin generates the loader entry. Plugin authors do not handle
C pointers, Lisp values or callback registration. See
[the example package](Examples/HelloPlugin/Package.swift) for the complete dynamic
library and build-plugin configuration. This initial API is intentionally small
and subject to change before release.

## Build and verify

Use official Xcode 27 with Swift 6.4 and a module-enabled Emacs installation on
macOS 27. From the repository root:

```sh
bash scripts/verify-toolchain.sh
swift build -Xswiftc -warnings-as-errors
bash Examples/HelloPlugin/run-native-tests.sh debug
bash Examples/HelloPlugin/run-native-tests.sh release
```

The verification gate records the compiler, SDK and OS, then compiles and runs
language probes. The example runner builds a real dynamic library and exercises
it in batch Emacs. A source inspection or Linux C syntax check is not a substitute
for these commands. CI uses GitHub's `xcode-27` runner and preserves evidence.

## Design and status

- [Boundary and concurrency architecture](docs/architecture.md)
- [Official tooling research and compiler evidence](docs/toolchain-research.md)
- [Project profile and contribution rules](docs/project-profile.md)
- [Integration test contracts](test/Native/README.md)

Use short-lived feature branches, Conventional Commits, linked issues and draft
PRs. Merge only verified, independently reviewed work, using squash merges.
Additional shared-library dependencies must come from Apple or the Swift language
organization's GitHub repositories.

## License and attribution

[GNU GPL version 3](LICENSE), with GPL-3.0-or-later terms in applicable source files.
This project derives from [Valeriy Savchenko's EmacsSwiftModule](https://github.com/SavchenkoValeriy/emacs-swift-module).
Existing source notices and the Free Software Foundation's Emacs header notices
are preserved. New implementation code carries GPL-3.0-or-later identifiers.
