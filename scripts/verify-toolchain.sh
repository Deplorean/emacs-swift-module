#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
output_dir="$repo_dir/.build/toolchain-verification"

if [[ $# -eq 2 && "$1" == "--output-dir" ]]; then
  output_dir="$2"
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--output-dir DIRECTORY]" >&2
  exit 2
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
rm -f "$output_dir/PASSED"

fail() {
  echo "Toolchain verification failed: $*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS 27 or newer is required."
architecture="$(uname -m)"
case "$architecture" in
  arm64|x86_64) ;;
  *) fail "unsupported macOS architecture: $architecture." ;;
esac
command -v python3 >/dev/null || fail "python3 is required to enforce probe timeouts."

host_version="$(/usr/bin/sw_vers -productVersion)"
[[ "${host_version%%.*}" =~ ^[0-9]+$ ]] || fail "unrecognized macOS version."
(( ${host_version%%.*} >= 27 )) || fail "host macOS must be at least 27."

xcode_version="$(/usr/bin/xcodebuild -version)"
[[ "$xcode_version" =~ ^Xcode[[:space:]]27([.][0-9]+)*[[:space:]] ]] ||
  fail "the selected Xcode must be version 27."
[[ -z "${TOOLCHAINS:-}" || "$TOOLCHAINS" == "com.apple.dt.toolchain.XcodeDefault" ]] ||
  fail "select the Apple XcodeDefault toolchain, not a custom TOOLCHAINS value."

compiler="$(/usr/bin/xcrun --find swiftc)"
frontend="$(/usr/bin/xcrun --find swift-frontend)"
developer_dir="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
developer_dir="$(cd "$developer_dir" && pwd -P)"
expected_bin="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin"
actual_bin="$(cd "$(dirname "$compiler")" && pwd -P)"
[[ "$actual_bin" == "$expected_bin" ]] ||
  fail "swiftc must come from the selected XcodeDefault toolchain."
[[ "$(cd "$(dirname "$frontend")" && pwd -P)" == "$expected_bin" ]] ||
  fail "swift-frontend must come from the selected XcodeDefault toolchain."

compiler_version="$("$compiler" --version)"
[[ "$compiler_version" =~ Apple[[:space:]]Swift[[:space:]]version[[:space:]]6[.]4([.][0-9]+)*[[:space:]] ]] ||
  fail "Apple Swift 6.4.x is required; no older or newer minor is accepted."
sdk_version="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
sdk_path="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
[[ "${sdk_version%%.*}" =~ ^[0-9]+$ ]] || fail "unrecognized macOS SDK version."
(( ${sdk_version%%.*} >= 27 )) || fail "macOS SDK 27 or newer is required."

{
  /bin/date -u '+Verified at: %Y-%m-%dT%H:%M:%SZ'
  /usr/bin/sw_vers
  /usr/bin/uname -m
  printf '%s\n' "$xcode_version" "$compiler_version"
  printf 'Developer directory: %s\nCompiler: %s\nFrontend: %s\nSDK: %s\nSDK path: %s\n' \
    "$developer_dir" "$compiler" "$frontend" "$sdk_version" "$sdk_path"
  printf 'Runner image: %s\nRunner image version: %s\n' \
    "${ImageOS:-not supplied}" "${ImageVersion:-not supplied}"
  if command -v git >/dev/null; then
    printf 'Source revision: '
    git -C "$repo_dir" rev-parse HEAD
    git -C "$repo_dir" status --short -- scripts/probes scripts/verify-toolchain.sh
  fi
} > "$output_dir/toolchain.txt"
cat "$output_dir/toolchain.txt"

# Verify the actual driver and frontend against Apple's signing trust anchor.
# A version string or an executable named swiftc is insufficient provenance.
: > "$output_dir/compiler-signatures.txt"
for executable in "$compiler" "$frontend"; do
  /usr/bin/codesign --verify --strict -R='anchor apple' "$executable" \
    >> "$output_dir/compiler-signatures.txt" 2>&1 ||
    fail "Apple signature verification failed for $executable."
  /usr/bin/codesign --display --verbose=4 "$executable" \
    >> "$output_dir/compiler-signatures.txt" 2>&1
done
cat "$output_dir/compiler-signatures.txt"
"$compiler" -print-target-info > "$output_dir/target-info.json"

flags=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors
  -sdk "$sdk_path" -target "$architecture-apple-macosx27.0")

run_probe() {
  local executable="$1"
  python3 - "$executable" <<'PY'
import subprocess
import sys

try:
    subprocess.run([sys.argv[1]], check=True, timeout=30)
except subprocess.TimeoutExpired:
    sys.exit("Probe exceeded its 30 second deadline: " + sys.argv[1])
except subprocess.CalledProcessError as error:
    sys.exit(error.returncode)
PY
}

for name in LanguageFeatures ObservationFeatures; do
  echo "Compiling and running $name"
  if ! "$compiler" "${flags[@]}" -parse-as-library "$script_dir/probes/$name.swift" \
      -o "$output_dir/$name" > "$output_dir/$name.log" 2>&1; then
    cat "$output_dir/$name.log"
    fail "$name did not compile."
  fi
  if ! run_probe "$output_dir/$name" >> "$output_dir/$name.log" 2>&1; then
    cat "$output_dir/$name.log"
    fail "$name did not complete successfully."
  fi
  cat "$output_dir/$name.log"
done

# Exercise the C ABI from a C translation unit, including the generated header.
echo "Compiling and running CExport"
if ! "$compiler" "${flags[@]}" -parse-as-library -emit-object \
    -emit-clang-header-path "$output_dir/CExport.h" -module-name CExport \
    "$script_dir/probes/CExport.swift" -o "$output_dir/CExport.o" \
    > "$output_dir/CExport.log" 2>&1; then
  cat "$output_dir/CExport.log"
  fail "the public @c attribute or generated C header failed."
fi
if ! /usr/bin/xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
    -isysroot "$sdk_path" -target "$architecture-apple-macosx27.0" -I "$output_dir" \
    -c "$script_dir/probes/CExportClient.c" -o "$output_dir/CExportClient.o" \
    >> "$output_dir/CExport.log" 2>&1; then
  cat "$output_dir/CExport.log"
  fail "the generated header could not be consumed by C."
fi
if ! "$compiler" "${flags[@]}" "$output_dir/CExport.o" "$output_dir/CExportClient.o" \
    -o "$output_dir/CExport" >> "$output_dir/CExport.log" 2>&1; then
  cat "$output_dir/CExport.log"
  fail "the Swift/C ABI probe did not link."
fi
if ! run_probe "$output_dir/CExport" >> "$output_dir/CExport.log" 2>&1; then
  cat "$output_dir/CExport.log"
  fail "the Swift function did not return the expected value to C."
fi
cat "$output_dir/CExport.log"

for name in RejectNonSendable RejectUseAfterConsume; do
  echo "Checking expected compiler rejection: $name"
  # Emit SIL rather than only typechecking: ownership diagnostics run after
  # typechecking, and must actually be exercised.
  if "$compiler" "${flags[@]}" -parse-as-library -emit-sil \
      "$script_dir/probes/$name.swift" -o "$output_dir/$name.sil" \
      > "$output_dir/$name.log" 2>&1; then
    fail "$name unexpectedly compiled."
  fi
  case "$name" in
    RejectNonSendable) pattern='does not conform.*Sendable|non-sendable|non-Sendable' ;;
    RejectUseAfterConsume) pattern='consumed more than once|used after consum' ;;
  esac
  /usr/bin/grep -Eiq "$pattern" "$output_dir/$name.log" ||
    fail "$name failed for a reason other than the expected safety diagnostic."
  cat "$output_dir/$name.log"
done

printf 'All compiler provenance, version, runtime, C ABI, and rejection probes passed.\n' \
  > "$output_dir/PASSED"
cat "$output_dir/PASSED"
