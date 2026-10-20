# Native plugin boundary

Status: implementation under verification in issue #5. This is not a release
readiness claim.

Plugin authors implement `Plugin`, providing a unique name and typed `Command`
closures. Swift `String` and `Int` cross the boundary by value. The build tool
supplies `emacs_module_init`; an internal C target supplies Emacs's GPL marker.
No `emacs_env`, raw value or callback registration is part of ordinary plugin code.
The first slice deliberately uses ordinary Swift closures rather than macros.
Macros can later improve declaration syntax after the execution contract is proven;
they do not solve foreign-runtime isolation or lifetime safety.

Every Emacs callback owns a fresh internal environment and scope. A scope is bound
to the entering pthread, expires before returning, and is checked before C access.
The boundary uses `defer` for invalidation even when commands throw. Values from
another callback are rejected. Neither the environment nor temporary values are
Sendable. `@MainActor` is not the Emacs executor.

Async command input is converted before spawning work. Only native Sendable data
and explicit global references may outlive the callback. Work requests return to
Emacs through a pipe process filter, which creates a new callback environment.
No detached Swift task calls the Emacs ABI. The queue and continuations use Swift's
Synchronization mutex; callbacks and continuation resumes happen outside locks.
Global-reference destruction enqueues addresses for release at an authorized Emacs
callback. Shutdown and cancellation need executable evidence for races and cleanup;
passing happy-path commands alone is insufficient for release acceptance.

An Emacs signal or throw must be preserved rather than replaced during unwind.
Native errors are translated at the callback boundary. Names, arity and conversions
are validated before invoking native closures. Reentrancy may create nested callback
scopes; scope identity must remain distinct even on the same thread.

The new source is original GPL-3.0-or-later work. The retained `emacs_module.h`
keeps its FSF copyright and GPL notice. Existing historical files retain their
original attribution until removed as superseded implementation; Git history
preserves the upstream work.

## Remaining release acceptance

- Executed debug/release real Emacs tests for conversions, errors, asynchronous
  completion, cancellation and shutdown.
- Swift unit/negative compiler tests for lifetime and Sendable boundaries.
- Thread/address sanitizer coverage and reentrant/error-path cleanup stress.
- Defined editor operations and supported native conversions beyond the first slice.
- Observation probes and an explicit decision about its public integration.
- Macro design decision and, if selected, SwiftSyntax 604 expansion/consumer tests.
- Native logging/performance policy, bounded resource handling, and license audit.
- Independent review tied to the tested commit, release notes and owner approval
  before publishing any release.
