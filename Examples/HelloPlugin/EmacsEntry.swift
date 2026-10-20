// SPDX-License-Identifier: GPL-3.0-or-later
internal import EmacsABI
internal import ModuleLicense

// Swift 6.4 validates this implementation against emacs_module.h.
@c @implementation
public func emacs_module_init(_ runtime: UnsafeMutablePointer<emacs_runtime>) -> CInt {
    emacs_swift_module_license_anchor()
    guard runtime.pointee.size >= MemoryLayout<emacs_runtime>.size else { return 1 }
    return 0
}
