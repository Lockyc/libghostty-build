#!/usr/bin/env bash
# Build Ghostty's libghostty static archive for one macOS arch, and stage the
# archive + C headers for xcframework assembly.
#
# Usage: build-target.sh <ghostty-source-dir> <zig-target> <output-dir>
#   zig-target: aarch64-macos | x86_64-macos
#
# Deliberately does NOT apply any patches — we build UNMODIFIED upstream Ghostty
# (macOS only). The flags mirror the known-good libghostty-spm build:
# app-runtime=none yields the embedding library (the C API warden links), not
# the app.
set -euo pipefail

SRC=${1:?ghostty source dir}
TARGET=${2:?zig target}
OUT=${3:?output dir}

command -v zig >/dev/null 2>&1 || { echo "[!] zig not found on PATH"; exit 1; }
[ -f "$SRC/include/ghostty.h" ] || { echo "[!] $SRC/include/ghostty.h missing — wrong ref or source dir"; exit 1; }

LOCAL_CACHE="$SRC/.zig-local-cache"
rm -rf "$OUT" "$SRC/zig-out" "$LOCAL_CACHE"
mkdir -p "$OUT/lib" "$OUT/include" "$LOCAL_CACHE"

echo "[*] zig build libghostty  target=$TARGET"
(
  cd "$SRC"
  ZIG_LOCAL_CACHE_DIR="$LOCAL_CACHE" \
  zig build \
    -Doptimize=ReleaseFast \
    -Dapp-runtime=none \
    -Demit-exe=false \
    -Demit-xcframework=false \
    -Demit-macos-app=false \
    -Demit-docs=false \
    -Dsentry=false \
    -Dtarget="$TARGET"
)

# Locate the built archive: zig-out first, else the local cache's object tree
# (Darwin app-runtime=none does not always install to zig-out).
LIB=""
if [ -f "$SRC/zig-out/lib/libghostty.a" ]; then
  LIB="$SRC/zig-out/lib/libghostty.a"
else
  LIB=$(find "$LOCAL_CACHE/o" -type f \( -name 'libghostty.a' -o -name 'libghostty-fat.a' \) 2>/dev/null | sort | tail -n 1)
fi
[ -n "$LIB" ] && [ -f "$LIB" ] || { echo "[!] could not locate built libghostty archive"; find "$LOCAL_CACHE" -maxdepth 3 -type f | sort | tail -n 30; exit 1; }

cp "$LIB" "$OUT/lib/libghostty.a"
cp "$SRC/include/ghostty.h" "$OUT/include/ghostty.h"
cat >"$OUT/include/module.modulemap" <<'EOF'
module libghostty {
    umbrella header "ghostty.h"
    export *
}
EOF

echo "[*] staged $TARGET → $OUT/lib/libghostty.a ($(du -h "$OUT/lib/libghostty.a" | cut -f1))"
