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

# Strip debug symbols: Zig's ReleaseFast archive carries ~220MB of DWARF that
# balloons the vendored binary (280MB -> ~48MB). `strip -S` removes only debug
# symbols; the exported ghostty_* C API stays intact, so static linking is
# unaffected. warden doesn't debug into libghostty; a symbolicated build can be
# reproduced from the pinned commit if ever needed.
echo "[*] before strip: $(du -h "$STAGE/libghostty.a" | cut -f1)"
strip -S "$STAGE/libghostty.a"
echo "[*] after strip:  $(du -h "$STAGE/libghostty.a" | cut -f1)"

xcodebuild -create-xcframework \
  -library "$STAGE/libghostty.a" -headers "$STAGE/Headers" \
  -output "$OUT/GhosttyKit.xcframework"
rm -rf "$STAGE"

echo "[*] repackaged slices: $(ls "$OUT/GhosttyKit.xcframework" | grep -v Info.plist | tr '\n' ' ')"
echo "[*] library: $(ls "$OUT/GhosttyKit.xcframework"/macos-*/*.a)"

# --- Ghostty resources (terminfo + shell-integration) -------------------------
#
# libghostty REQUIRES these at runtime to identify itself as ghostty. It climbs
# from the running executable looking for the sentinel
# `Contents/Resources/terminfo/78/xterm-ghostty`; without it, `resourcesDir()`
# returns null and Subprocess.init falls back to `TERM=xterm-256color` (it even
# logs "ghostty terminfo not found, using xterm-256color"). That fallback is not
# cosmetic: xterm-256color has no `Sync` capability, so tmux never wraps its
# redraws in DEC mode 2026, libghostty renders half-drawn frames, and an
# unfocused surface paints its hollow cursor at whatever mid-repaint position it
# sampled. A host app must ship these to be a correct libghostty embedder.
#
# Ghostty's own xcframework graph already installs them ("the xcframework build
# always installs resources", build.zig) — we only collect them. Themes/docs are
# NOT emitted (emit_themes/emit_docs default off) and warden exposes no ghostty
# theme config, so the payload is just the two dirs the runtime actually reads.
RES="$OUT/GhosttyResources"
rm -rf "$RES"
mkdir -p "$RES"

SHARE="$SRC/zig-out/share"
[ -d "$SHARE/terminfo" ] || { echo "[!] $SHARE/terminfo missing — did the resources install step run?"; ls -la "$SHARE" 2>/dev/null; exit 1; }
[ -d "$SHARE/ghostty/shell-integration" ] || { echo "[!] $SHARE/ghostty/shell-integration missing"; ls -la "$SHARE/ghostty" 2>/dev/null; exit 1; }

# -R preserves the symlinks tic writes into the terminfo db.
cp -R "$SHARE/terminfo" "$RES/terminfo"
mkdir -p "$RES/ghostty"
cp -R "$SHARE/ghostty/shell-integration" "$RES/ghostty/shell-integration"

# The sentinel libghostty actually probes for. If this is absent the whole
# exercise is pointless (silent TERM fallback), so fail the build, not the app.
[ -e "$RES/terminfo/78/xterm-ghostty" ] || { echo "[!] terminfo sentinel 78/xterm-ghostty missing — tic did not compile the entry"; find "$RES/terminfo" | head; exit 1; }

echo "[*] resources: $(find "$RES" -type f -o -type l | wc -l | tr -d ' ') files, $(du -sh "$RES" | cut -f1)"
echo "[*] terminfo entries: $(find "$RES/terminfo" -mindepth 2 -exec basename {} \; | sort -u | tr '\n' ' ')"
