# libghostty-build

CI that builds [Ghostty](https://github.com/ghostty-org/ghostty)'s embedding library from a
**pinned, unmodified upstream commit** and publishes it as a release asset.

It builds the macOS **`GhosttyKit.xcframework`** — Ghostty's embedding framework (terminal
surfaces, the `ghostty_surface_*` C API, the NSView host) — for
[warden](https://github.com/lockyc/warden), which embeds libghostty as its terminal surface.
Upstream Ghostty's releases carry only the app and `ghostty-vt` (the VT sublibrary), not this
framework. The repo ships no library source of its own; the deliverable is the release asset.

## What it produces

Each Ghostty pin publishes one release tagged `ghostty-<short-sha>` (the newest is GitHub's "latest"),
carrying **three** assets — each zipped, with a `.sha256` and a build-provenance attestation:

- **`GhosttyKit.xcframework.zip`** — the universal (arm64 + x86_64) macOS `GhosttyKit.xcframework`
  (slice `macos-arm64_x86_64`).
- **`GhosttyResources.zip`** — libghostty's **runtime resources**: `terminfo/` (tic-compiled) plus
  `ghostty/shell-integration/`, laid out to unpack straight into an embedder's `Contents/Resources`.
- **`libghostty-vt-macos.zip`** — libghostty-vt, Ghostty's standalone VT library: a universal macOS
  `lib/libghostty-vt.a` plus `include/ghostty/vt.h` and `vt/`, built with `-Demit-lib-vt` for
  [warden](https://github.com/lockyc/warden)'s `warden-relay` helper.

**Embedders must ship the resources.** Without `Contents/Resources/terminfo/78/xterm-ghostty`,
libghostty sets **`TERM=xterm-256color`** instead of `xterm-ghostty` (logging *"ghostty terminfo not
found, using xterm-256color"*), and programs in the terminal lose **synchronized output
(DEC 2026)**, styled/coloured underlines, and shell integration — tmux then shows half-drawn frames
and a flickering cursor in unfocused panes.

## How the build works

1. **`GHOSTTY_REF`** (a one-line file at the repo root) — the Ghostty ref (tag or SHA) to build.
2. **`.github/workflows/build.yml`** (manual `workflow_dispatch`; optional ref override) on
   **`macos-15`** with the Zig version Ghostty's `build.zig.zon` requires at that SHA:
   - resolves the ref → SHA and clones **unmodified** Ghostty at it,
   - runs `scripts/build-xcframework.sh`, which invokes Ghostty's own xcframework build
     (`-Demit-xcframework`), unpatched,
   - takes the universal (arm64 + x86_64) macOS library out of it and repackages it as a
     macOS-only xcframework with the archive named `libghostty.a` (the compiled library is
     unchanged),
   - collects the runtime resources from `zig-out/share`,
   - zips, checksums, attests, and publishes the release.

## Bumping the Ghostty version

Edit `GHOSTTY_REF` to a newer commit/tag, commit, and run the workflow (Actions ▸ *Build GhosttyKit*
▸ *Run workflow*). To test a ref without changing the pin, pass it as the `ghostty_ref` input; that build
publishes as a prerelease, so warden (which vendors the latest release) never picks it up.
`.github/workflows/ghostty-tag-watch.yml` checks weekly and opens a `ghostty-update` issue when
Ghostty tags a new stable release.

To add libghostty-vt to a release that already exists without rebuilding its other assets, run the
workflow with `vt_only` ticked (and `ghostty_ref` set to the pinned ref).

## Consuming it (warden)

warden pulls all three latest-release assets (the xcframework it links, the resources it
bundles into `warden.app/Contents/Resources`, and libghostty-vt) into `crates/warden-app/vendor/` via
`just revendor-ghostty`, checking each against its `.sha256`. See warden's `vendor/PROVENANCE.md`.

## Licensing

The build scripts and workflow here are MIT (`LICENSE`). The **published assets contain compiled
Ghostty and its runtime resources**, MIT-licensed by upstream; its notice travels with the binary
(`LICENSE-ghostty`). This repo redistributes those files under that license.
