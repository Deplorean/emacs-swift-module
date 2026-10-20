<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
Explanation for framework maintainers: why the first command API is Swift-only.

# About the command boundary

Issue #1 needs a compile-tested Swift author experience before binding it to
Emacs's foreign runtime. `Command` holds only native Swift values and Sendable
closures. The internal adapter can later convert callback-local Emacs values at
its boundary without exposing pointers or thread rules to plugin authors.

The C declarations in `emacs_module.h` are imported automatically by Swift's
interoperability tooling. This package does not implement a parallel C or C++
conversion library. The separate adapter will provide only the loader and
callback glue required by Emacs.

Macro syntax remains an evaluation item. Ordinary Swift declarations provide
a clear behavior contract that a future macro can generate without changing
the conversion rules. The runtime still needs an independently reviewed
ownership and async shutdown design before a release candidate exists.
