# libghostty-build

CI that builds [Ghostty](https://github.com/ghostty-org/ghostty)'s embedding library from a
**pinned, unmodified upstream commit** and publishes it as a release asset.

Today it builds the macOS **`GhosttyKit.xcframework`** — Ghostty's embedding framework (terminal
surfaces, the `ghostty_surface_*` C API, the NSView host). The name is platform-neutral on purpose:
if [warden](https://github.com/lockyc/warden) ever needs a libghostty for another platform, its build
lands here too, rather than forcing a rename.

## Why this exists

warden embeds libghostty as its terminal surface. Upstream Ghostty does **not** publish the full
embedding framework as a downloadable artifact — its releases carry only the app and `ghostty-vt`
(the VT sublibrary). So the framework has to be **built from Ghostty's source** (`GhosttyKit` is a
first-class `zig build` target). This repo does exactly that, on a commit *we* pin, so warden:

- tracks Ghostty on **its own schedule** (bump `GHOSTTY_REF`, re-run) instead of waiting on a
  third-party repackage, and
- links a binary built from **known, unmodified upstream** with GitHub **build-provenance
  attestation** — not a third party's self-attested prebuilt.

This is a build-tooling repo. It ships no library source of its own; the deliverable is the release
asset.

## What it produces

Each Ghostty pin publishes one release tagged `ghostty-<short-sha>` (the newest is GitHub's "latest"),
carrying **two** assets — each zipped, with a `.sha256` and a build-provenance attestation:

- **`GhosttyKit.xcframework.zip`** — the universal (arm64 + x86_64) macOS `GhosttyKit.xcframework`
  (slice `macos-arm64_x86_64`, matching what warden's `build.rs` links).
- **`GhosttyResources.zip`** — libghostty's **runtime resources**: `terminfo/` (tic-compiled) plus
  `ghostty/shell-integration/`, laid out to unpack straight into an embedder's `Contents/Resources`.

**The resources aren't decoration — an embedder that ships only the library is a broken libghostty
host.** At surface spawn libghostty climbs from its executable looking for the sentinel
`Contents/Resources/terminfo/78/xterm-ghostty`; absent that, it exports **`TERM=xterm-256color`**
rather than `xterm-ghostty` (logging *"ghostty terminfo not found, using xterm-256color"*). Every
program in the terminal then believes it's talking to a plain xterm and loses **synchronized output
(DEC 2026)**, styled/coloured underlines, and shell integration. Synchronized output is the sharp
edge: without it tmux never brackets its redraws, so libghostty renders half-drawn frames — and an
unfocused surface, which paints its hollow cursor on *every* frame, flickers that cursor at whatever
mid-repaint position it happened to sample.

## How the build works

1. **`GHOSTTY_REF`** — the single source of truth: the exact Ghostty commit SHA to build.
2. **`.github/workflows/build.yml`** (manual `workflow_dispatch`; optional ref override) on
   **`macos-15`** with **Zig 0.15.2**:
   - resolves the ref → SHA and clones **unmodified** Ghostty at it,
   - runs `scripts/build-xcframework.sh`, which invokes Ghostty's **own** native xcframework build
     graph (`-Demit-xcframework`; `xcframework-target` defaults to `universal`, so one build
     cross-compiles both arches) — no per-arch `lipo`, no patches,
   - **repackages** Ghostty's universal macOS library into a lean, macOS-only xcframework with the
     archive named `libghostty.a` (Ghostty now ships it as `ghostty-internal.a`, and its native
     xcframework also bundles unused iOS slices; warden's `build.rs` links a macOS-only `libghostty.a`).
     The compiled bytes are untouched — only the wrapper filename and slice set change,
   - **collects the runtime resources** Ghostty's own xcframework graph already installs into
     `zig-out/share` (its build always installs them, since Ghostty's Xcode project references them),
   - zips, checksums, attests, and publishes the release.

**Runner choice is load-bearing.** Ghostty pins Zig 0.15.2, which could not link a **macOS 26** SDK
locally — so the build runs on `macos-15` (Sequoia), whose 15.x SDK Zig 0.15.2 links cleanly. That
runner-OS choice is the whole reason a local build was blocked but CI isn't.

## Bumping the Ghostty version

Edit `GHOSTTY_REF` to a newer commit/tag, commit, and run the workflow (Actions ▸ *Build GhosttyKit*
▸ *Run workflow*). To test a ref without changing the pin, pass it as the `ghostty_ref` input.

## Consuming it (warden)

warden pulls **both** latest-release assets into `crates/warden-app/vendor/` via
`just revendor-ghostty`, verifying each `.sha256`: the xcframework it links, and the resources it
bundles into `warden.app/Contents/Resources`. See warden's `vendor/PROVENANCE.md`.

## Licensing

The build scripts and workflow here are MIT (`LICENSE`). The **published `GhosttyKit.xcframework`
contains compiled Ghostty**, which is MIT-licensed by upstream; its notice travels with the binary
(`LICENSE-ghostty`). This repo redistributes Ghostty's compiled bytes under that license.
