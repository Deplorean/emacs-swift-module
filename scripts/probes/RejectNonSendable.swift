// SPDX-License-Identifier: GPL-3.0-or-later
// This file must fail compilation with a Sendable diagnostic.

final class MutableReference {
  var value = 0
}

func acceptsSendable<T: Sendable>(_ value: T) {}

func violateSendability() {
  acceptsSendable(MutableReference())
}
