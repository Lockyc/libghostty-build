# libghostty-build

[![Release](https://img.shields.io/github/v/release/lockyc/libghostty-build?label=release)](https://github.com/lockyc/libghostty-build/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS-555)
[![License](https://img.shields.io/github/license/lockyc/libghostty-build)](LICENSE)

CI that builds [Ghostty](https://github.com/ghostty-org/ghostty)'s embedding library from a
**pinned, unmodified upstream commit** and publishes it as a release asset. Upstream Ghostty's
releases carry only the app and `ghostty-vt`, not the macOS `GhosttyKit.xcframework` an app needs
to embed Ghostty's terminal surfaces. The repo ships no library source of its own; the
deliverable is the release.

## What it produces

Each Ghostty pin publishes one release tagged `ghostty-<short-sha>`; the current pin's release is
GitHub's "latest", and a test build of another ref is a prerelease. Each carries **three** assets,
zipped, each with a `.sha256` and a build-provenance attestation:

- **`GhosttyKit.xcframework.zip`** — the universal (arm64 + x86_64) macOS `GhosttyKit.xcframework`
  (slice `macos-arm64_x86_64`): terminal surfaces, the `ghostty_surface_*` C API, the NSView host.
- **`GhosttyResources.zip`** — libghostty's **runtime resources**: `terminfo/` (tic-compiled) plus
  `ghostty/shell-integration/`, laid out to unpack straight into an app's `Contents/Resources`.
- **`libghostty-vt-macos.zip`** — libghostty-vt, Ghostty's standalone VT library: a universal
  `lib/libghostty-vt.a` plus `include/ghostty/vt.h` and `vt/`.

**Embedders must ship the resources.** Without `Contents/Resources/terminfo/78/xterm-ghostty`,
libghostty sets **`TERM=xterm-256color`** instead of `xterm-ghostty` (logging *"ghostty terminfo not
found, using xterm-256color"*), and programs in the terminal lose **synchronized output
(DEC 2026)**, styled/coloured underlines, and shell integration — tmux then shows half-drawn frames
and a flickering cursor in unfocused panes.

## Use

```bash
gh release download --repo lockyc/libghostty-build --pattern '*.zip' --pattern '*.sha256'
shasum -a 256 -c *.sha256
gh attestation verify GhosttyKit.xcframework.zip --repo lockyc/libghostty-build
```

Pass a tag (`gh release download ghostty-<short-sha> …`) to pin one build instead of the latest.
[warden](https://github.com/lockyc/warden) consumes all three with `just revendor-ghostty`, which
checks each `.sha256` and records the Ghostty ref in its `vendor/PROVENANCE.md`.

## How the build works

`GHOSTTY_REF`, a one-line file at the repo root, names the Ghostty tag or SHA to build.
`.github/workflows/build.yml` (run by hand, on **`macos-15`**, with the Zig version Ghostty's
`build.zig.zon` requires at that SHA):

1. resolves the ref to a SHA and clones **unmodified** Ghostty at it;
2. runs Ghostty's own xcframework build (`-Demit-xcframework`), unpatched, and repackages the
   universal macOS library as a macOS-only xcframework with the archive named `libghostty.a`
   (the compiled library is unchanged);
3. collects the runtime resources from `zig-out/share`;
4. builds libghostty-vt (`-Demit-lib-vt`) for aarch64 and x86_64 and `lipo`s them into one
   universal library;
5. zips, checksums, attests and publishes the release.

To move the pin, edit `GHOSTTY_REF`, commit, and run the workflow. A weekly workflow opens a
`ghostty-update` issue when Ghostty tags a new stable release. Test builds, rebuilding one asset,
and the rest of the maintainer runbook: [CLAUDE.md](CLAUDE.md).

## License

The build scripts and workflow here are MIT ([LICENSE](LICENSE)). The **published assets contain
compiled Ghostty and its runtime resources**, MIT-licensed by upstream; its notice travels with
the binary (`LICENSE-ghostty`). This repo redistributes those files under that license.
