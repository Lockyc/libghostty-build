#!/usr/bin/env bash
# Build libghostty-vt (Ghostty's standalone VT library: terminal state, snapshot
# encode/decode, formatter) as a universal macOS static library from an UNMODIFIED
# Ghostty source tree, and stage it with its headers into <output-dir>/libghostty-vt/.
#
# Usage: build-vt.sh <ghostty-source-dir> <output-dir>
#
# `-Demit-lib-vt=true` installs `lib/libghostty-vt.a` for ONE target per build, so
# we build aarch64 and x86_64 separately and lipo them: the same arch pair as the
# xcframework slice, and the same ghostty source graph, no patches.
set -euo pipefail

SRC=${1:?ghostty source dir}
OUT=${2:?output dir}

command -v zig >/dev/null 2>&1 || { echo "[!] zig not found on PATH"; exit 1; }
[ -f "$SRC/include/ghostty/vt.h" ] || { echo "[!] $SRC/include/ghostty/vt.h missing — wrong ref or source dir"; exit 1; }

STAGE="$OUT/libghostty-vt"
rm -rf "$STAGE" "$OUT/.vt-build"
mkdir -p "$STAGE/lib" "$STAGE/include" "$OUT/.vt-build"

for arch in aarch64 x86_64; do
  echo "[*] zig build -Demit-lib-vt ($arch-macos)"
  ( cd "$SRC" && zig build \
      -Doptimize=ReleaseFast \
      -Demit-lib-vt=true \
      -Dtarget="$arch-macos" \
      --prefix "$OUT/.vt-build/$arch" )
  [ -f "$OUT/.vt-build/$arch/lib/libghostty-vt.a" ] \
    || { echo "[!] $arch libghostty-vt.a not produced"; find "$OUT/.vt-build/$arch" | head -30; exit 1; }
done

lipo -create "$OUT/.vt-build/aarch64/lib/libghostty-vt.a" "$OUT/.vt-build/x86_64/lib/libghostty-vt.a" \
  -output "$STAGE/lib/libghostty-vt.a"
echo "[*] archs: $(lipo -archs "$STAGE/lib/libghostty-vt.a")"

# Debug symbols only (same reasoning as the xcframework: DWARF dominates the size and
# the exported ghostty_* C API is untouched).
echo "[*] before strip: $(du -h "$STAGE/lib/libghostty-vt.a" | cut -f1)"
strip -S "$STAGE/lib/libghostty-vt.a"
echo "[*] after strip:  $(du -h "$STAGE/lib/libghostty-vt.a" | cut -f1)"

mkdir -p "$STAGE/include/ghostty"
cp "$SRC/include/ghostty/vt.h" "$STAGE/include/ghostty/vt.h"
cp -R "$SRC/include/ghostty/vt" "$STAGE/include/ghostty/vt"
rm -rf "$OUT/.vt-build"

# The two entry points warden-relay links; fail the build, not the consumer, if absent.
nm -g "$STAGE/lib/libghostty-vt.a" 2>/dev/null | grep -q ' T _ghostty_snapshot_decoder_new$' \
  || { echo "[!] ghostty_snapshot_decoder_new not defined in libghostty-vt.a"; exit 1; }
nm -g "$STAGE/lib/libghostty-vt.a" 2>/dev/null | grep -q ' T _ghostty_formatter_terminal_new$' \
  || { echo "[!] ghostty_formatter_terminal_new not defined in libghostty-vt.a"; exit 1; }
echo "[*] libghostty-vt staged: $STAGE"
