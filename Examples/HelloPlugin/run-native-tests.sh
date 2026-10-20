#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

example_directory="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(CDPATH= cd -- "$example_directory/../.." && pwd)"
configuration="${1:-debug}"
swift_command="${SWIFT:-swift}"
emacs_command="${EMACS:-emacs}"

if [[ $# -gt 1 || ( "$configuration" != debug && "$configuration" != release ) ]]; then
  printf 'Usage: %s [debug|release]\n' "$0" >&2
  exit 2
fi

command -v "$swift_command" >/dev/null
command -v "$emacs_command" >/dev/null

"$swift_command" build \
  --package-path "$example_directory" \
  --configuration "$configuration" \
  --product HelloPlugin
binary_directory="$("$swift_command" build \
  --package-path "$example_directory" \
  --configuration "$configuration" \
  --show-bin-path)"
module_path="$binary_directory/libHelloPlugin.dylib"

if [[ ! -f "$module_path" ]]; then
  printf 'Expected the macOS dynamic module at %s\n' "$module_path" >&2
  exit 1
fi

# Shutdown is intentionally tested in its own Emacs process.
for suite in hello-plugin-tests.el hello-plugin-shutdown-tests.el; do
  HELLO_PLUGIN_MODULE="$module_path" "$emacs_command" \
    --quick --batch \
    --load "$repository_directory/test/Native/$suite" \
    --eval '(ert-run-tests-batch-and-exit t)'
done
