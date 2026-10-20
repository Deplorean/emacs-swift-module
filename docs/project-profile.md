# Engineering profile

The owner-approved target is Swift **6.4** in Swift 6 language mode and macOS
**27.0** minimum. Xcode 27 and real module-enabled Emacs are required for acceptance.
This branch is an in-progress replacement; the default branch remains unchanged.

GitHub issues #1–#5 are the work and acceptance records. Use feature branches,
Conventional Commits, draft PRs, independent review, and verified squash merges.
Never publish releases without owner authorization.

- Framework: `Source/SwiftNative`, internal C declarations: `Source/C`.
- Generated entry: `Plugins`; C loader marker: `Source/PluginSupport`.
- Integration consumer: `Examples/HelloPlugin`; acceptance tests: `test/Native`.
- Toolchain gates and compiler probes: `scripts`; research/design: `docs`.
- Verify: `bash scripts/verify-toolchain.sh`, `swift build -Xswiftc
  -warnings-as-errors`, `bash Examples/HelloPlugin/run-native-tests.sh`.
- CI: `.github/workflows/native.yml`, verified runtime on the `xcode-27` image.

Preserve the repository GPL license, existing source notices, and FSF header.
New original code uses `SPDX-License-Identifier: GPL-3.0-or-later`. Any added
shared library must come from Apple's or the Swift language organization's GitHub
repositories; record its exact version, source and license before use. Prefer
standard-library concurrency, Synchronization and native OSLog where sufficient.

The first owner review milestone is an actual end-to-end example plugin. It is
not equivalent to release acceptance: outstanding features and verification must
remain explicitly tracked. No persistent execution is configured for this session.
