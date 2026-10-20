<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
Reference for maintainers verifying the Swift 6.4 / Xcode 27 / macOS 27 baseline.

# Toolchain evidence and probes

Sources checked on 2026-10-20. Availability evidence is distinct from a successful build of this repository.

| Requirement | Official evidence |
| --- | --- |
| Swift 6.4 | [Swift release announcement](https://www.swift.org/blog/swift-6.4-released/) dated September 15, 2026. The release includes async `defer` and advanced Observation. |
| Xcode 27 | [Apple's SDK and system requirements](https://developer.apple.com/xcode/system-requirements) list Swift 6.4, Swift 6 language mode, and the macOS 27 SDK. |
| macOS 27 CI | [GitHub's October 15 announcement](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/) makes `xcode-27` generally available on Apple Silicon and macOS 27. |
| Selected Xcode | The [runner image manifest](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md) documents Xcode 27.0 at `/Applications/Xcode_27.app`, with `/Applications/Xcode_27.0.app` as a symlink. The image changes over time. |
| Macro implementation | [SwiftSyntax 604.0.0](https://github.com/swiftlang/swift-syntax/releases/tag/604.0.0) is a stable release; the [project's release policy](https://github.com/swiftlang/swift-syntax#releases) aligns versions with Swift tooling. |

## Verification command

`scripts/verify-toolchain.sh [--output-dir DIRECTORY]` defaults to `.build/toolchain-verification`. It requires macOS 27 or newer, Xcode major version 27, Apple Swift compiler minor version **6.4**, and SDK 27 or newer. It uses Swift 6 language mode, the host architecture, and a macOS 27 deployment target. GitHub's `xcode-27` image provides arm64 evidence. There are no fallback toolchain versions or skipped feature probes.

The script checks that both the driver and compiler frontend reside in the selected Xcode default toolchain, and verifies their signatures against Apple's trust anchor using `codesign`. It records host, SDK, Xcode, compiler, target, and runner-image evidence. These checks establish the compiler selected for this run; a version string alone does not.

| Probe | Verification |
| --- | --- |
| `LanguageFeatures.swift` | Compiles and runs actor-isolated concurrent updates, a noncopyable value with borrowing/consuming operations, and awaited cleanup in `defer`. |
| `ObservationFeatures.swift` | Compiles and runs `@Observable` macro expansion, options-based `.didSet` notification, key-path matching, and continuous initial/change delivery. Consumes the observation token through cancellation. |
| `CExport.swift` / `CExportClient.c` | Generates a C header from a public `@c` function, compiles a separate C caller, links both objects, and executes the C-to-Swift call. |
| `RejectNonSendable.swift` | Must fail with a Sendable diagnostic under complete strict concurrency. |
| `RejectUseAfterConsume.swift` | Must fail with an ownership diagnostic when the same value is consumed twice. |

Each runnable probe has a 30-second deadline. Every probe must succeed, including expected diagnostic checks, before the script writes `PASSED`. Logs and executables remain in the output directory for CI artifacts. The probes supplement package, macro, and real Emacs integration tests; they do not replace those tests or prove arbitrary code thread-safe.

## Version-specific API details

The [SE-0506 proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0506-advanced-observation-tracking.md) is implemented in Swift 6.4. Its continuous-observation spelling differs from the shipped API. Use [`withContinuousObservation(options:apply:)`](https://developer.apple.com/documentation/observation/withcontinuousobservation(options:apply:)).

The [Swift 6.4 release source](https://github.com/swiftlang/swift/blob/swift-6.4.0-RELEASE/stdlib/public/Observation/Sources/Observation/ContinuousObservation.swift) returns a noncopyable token and schedules observation through an actor-aware asynchronous runner. The callback must read the properties being tracked. Token destruction and cancellation stop tracking. The probe waits for initial delivery before mutation; it does not assume synchronous delivery or test exhaustive cancellation races.

The [options-taking tracking implementation](https://github.com/swiftlang/swift/blob/swift-6.4.0-RELEASE/stdlib/public/Observation/Sources/Observation/ObservationTracking.swift) supports mutation and deinitialization options and a borrowed, noncopyable event. Such events must not escape into a queued Emacs callback.

[`@c` is specified by SE-0495](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md), implemented in Swift 6.3 and available in this baseline. Its optional C name is an identifier, not a string. Changing an existing `@_cdecl` API to `@c` can alter its Swift ABI; the standalone probe does not authorize or perform that migration.

## Validation status and provenance

The probe source and shell gate are original contributions under the repository license. The links above document APIs and release facts; no upstream implementation was copied.

Development of this gate occurred on a Linux host without Swift, Xcode, or Emacs. Shell syntax and rejection of that unsupported host can be checked there. Compilation and runtime success must be established by a macOS CI run; the existence of these files is not a passing result. A future run's `PASSED` artifact applies only to the source revision and environment recorded by that run.
