// SPDX-License-Identifier: GPL-3.0-or-later
// This file must fail compilation with an ownership diagnostic.

struct SingleOwner: ~Copyable {
  let value: Int
}

func consumeTwice(_ owner: consuming SingleOwner) -> Int {
  let first = consume owner
  let second = consume owner
  return first.value + second.value
}
