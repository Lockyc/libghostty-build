#!/usr/bin/env bash
# Build Ghostty's GhosttyKit.xcframework (universal macOS: arm64 + x86_64) from
# an UNMODIFIED Ghostty source tree, using Ghostty's own native xcframework
# build graph, and stage it into <output-dir>.
#
# Usage: build-xcframework.sh <ghostty-source-dir> <output-dir>
#
# We let Ghostty emit the xcframework itself (-Demit-xcframework):
# xcframework-target defaults to `universal`, so a single build cross-compiles
# both macOS arches and assembles the framework. No patches — the compiled
# libghostty bytes are exactly upstream's.
#
# We then REPACKAGE (not modify) Ghostty's universal macOS library into the lean
# shape warden vendors, for two reasons the raw output doesn't satisfy:
#   * Ghostty ships the macOS static archive as `ghostty-internal.a`, but
#     warden's build.rs does `link-lib=static=ghostty` → needs `libghostty.a`.
#   * Ghostty's xcframework also bundles iOS slices warden never uses (~130MB).
# So we extract the macOS-universal archive, name it `libghostty.a`, and rebuild
# a macOS-only xcframework around it. The library bytes are untouched; only the
# wrapper filename and slice set change.
set -euo pipefail

SRC=${1:?ghostty source dir}
OUT=${2:?output dir}

command -v zig >/dev/null 2>&1 || { echo "[!] zig not found on PATH"; exit 1; }
[ -f "$SRC/include/ghostty.h" ] || { echo "[!] $SRC/include/ghostty.h missing — wrong ref or source dir"; exit 1; }

rm -rf "$SRC/zig-out" "$SRC/macos/GhosttyKit.xcframework"

echo "[*] zig build -Demit-xcframework (universal)"
(
  cd "$SRC"
  zig build \
    -Doptimize=ReleaseFast \
    -Demit-xcframework=true \
    -Dxcframework-target=universal \
    -Demit-exe=false \
    -Demit-macos-app=false \
    -Demit-docs=false \
    -Dsentry=false
)

# Ghostty installs the framework to macos/GhosttyKit.xcframework (out_path);
# search zig-out too in case the install prefix changes.
XCF=$(find "$SRC/macos" "$SRC/zig-out" -type d -name 'GhosttyKit.xcframework' 2>/dev/null | head -n 1)
[ -n "$XCF" ] || { echo "[!] GhosttyKit.xcframework not found after build"; find "$SRC" -type d -name '*.xcframework' 2>/dev/null | head; exit 1; }
echo "[*] Ghostty built: $XCF"
echo "[*] raw slices: $(ls "$XCF" | grep -v Info.plist | tr '\n' ' ')"

# Locate the macOS-universal slice + its static archive (name may drift across
# Ghostty versions — find the .a rather than hard-code `ghostty-internal.a`).
MSLICE="$XCF/macos-arm64_x86_64"
[ -d "$MSLICE" ] || { echo "[!] macos-arm64_x86_64 slice missing (universal build expected)"; ls "$XCF"; exit 1; }
LIB=$(find "$MSLICE" -maxdepth 1 -name '*.a' | head -n 1)
[ -n "$LIB" ] || { echo "[!] no static archive in $MSLICE"; ls "$MSLICE"; exit 1; }
echo "[*] macOS archive: $(basename "$LIB")  archs: $(lipo -archs "$LIB")"

# Repackage macOS-only, library renamed to libghostty.a (bytes untouched).
STAGE="$OUT/.stage"
rm -rf "$STAGE" "$OUT/GhosttyKit.xcframework"
mkdir -p "$STAGE"
cp "$LIB" "$STAGE/libghostty.a"
cp -R "$MSLICE/Headers" "$STAGE/Headers"
xcodebuild -create-xcframework \
  -library "$STAGE/libghostty.a" -headers "$STAGE/Headers" \
  -output "$OUT/GhosttyKit.xcframework"
rm -rf "$STAGE"

echo "[*] repackaged slices: $(ls "$OUT/GhosttyKit.xcframework" | grep -v Info.plist | tr '\n' ' ')"
echo "[*] library: $(ls "$OUT/GhosttyKit.xcframework"/macos-*/*.a)"
