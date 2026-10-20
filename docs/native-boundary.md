# First compiler boundary

Issue #2 requires proof that the shipped Swift 6.4 compiler accepts the Emacs
C declaration as a Swift implementation. The first CI gate compiles `@c
@implementation` against the retained GNU Emacs header and links a dynamic
module containing the required GPL compatibility marker. The Swift Testing
target checks that the package can be consumed in Swift 6 language mode.

The marker is a C data symbol because Emacs requires that specific exported
variable. The function implementation is Swift and compiler checked against
the official C declaration. No C++ code is needed for this C API.

This is an interoperability gate, not yet a working plugin. Command
registration, conversions, async lifecycle, and an Emacs integration test are
still required before the first plugin checkpoint.
