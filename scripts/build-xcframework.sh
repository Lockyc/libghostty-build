#!/usr/bin/env bash
# Build Ghostty's GhosttyKit.xcframework (universal macOS: arm64 + x86_64) from
# an UNMODIFIED Ghostty source tree, using Ghostty's own native xcframework
# build graph, and stage it into <output-dir>.
#
# Usage: build-xcframework.sh <ghostty-source-dir> <output-dir>
#
# We deliberately let Ghostty emit the xcframework itself (-Demit-xcframework):
# xcframework-target defaults to `universal`, so a single build cross-compiles
# both arches and assembles the framework (slice `macos-arm64_x86_64`, headers
# included) — the exact shape warden's build.rs links. No manual lipo /
# xcodebuild, no patches.
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

mkdir -p "$OUT"
rm -rf "$OUT/GhosttyKit.xcframework"
cp -R "$XCF" "$OUT/GhosttyKit.xcframework"

echo "[*] built: $XCF"
echo "[*] slices: $(ls "$OUT/GhosttyKit.xcframework" | grep -v Info.plist | tr '\n' ' ')"
