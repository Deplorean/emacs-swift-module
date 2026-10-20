// SPDX-License-Identifier: GPL-3.0-or-later
#include "CExport.h"
#include <stdio.h>

int main(void) {
  if (emacs_swift_probe_sum(19, 23) != 42) {
    return 1;
  }
  puts("PASS: generated C header, exported symbol, and Swift-to-C calling convention");
  return 0;
}
