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

A universal (arm64 + x86_64) macOS `GhosttyKit.xcframework` (slice `macos-arm64_x86_64`, matching what
warden's `build.rs` links), zipped, with a `.sha256` and a build-provenance attestation. Each Ghostty
pin publishes one release tagged `ghostty-<short-sha>`; the newest is GitHub's "latest".

## How the build works

1. **`GHOSTTY_REF`** — the single source of truth: the exact Ghostty commit SHA to build.
2. **`.github/workflows/build.yml`** (manual `workflow_dispatch`; optional ref override) on
   **`macos-15`** with **Zig 0.15.2**:
   - resolves the ref → SHA and clones **unmodified** Ghostty at it,
   - runs `scripts/build-xcframework.sh`, which invokes Ghostty's **own** native xcframework build
     graph (`-Demit-xcframework`; `xcframework-target` defaults to `universal`, so one build
     cross-compiles both arches and assembles the framework with headers) — no manual `lipo` /
     `xcodebuild`, no patches,
   - zips, checksums, attests, and publishes the release.

**Runner choice is load-bearing.** Ghostty pins Zig 0.15.2, which could not link a **macOS 26** SDK
locally — so the build runs on `macos-15` (Sequoia), whose 15.x SDK Zig 0.15.2 links cleanly. That
runner-OS choice is the whole reason a local build was blocked but CI isn't.

## Bumping the Ghostty version

Edit `GHOSTTY_REF` to a newer commit/tag, commit, and run the workflow (Actions ▸ *Build GhosttyKit*
▸ *Run workflow*). To test a ref without changing the pin, pass it as the `ghostty_ref` input.

## Consuming it (warden)

warden pulls the latest release asset into `crates/warden-app/vendor/` via `just revendor-ghostty`,
verifying the `.sha256`. See warden's `vendor/PROVENANCE.md`.

## Licensing

The build scripts and workflow here are MIT (`LICENSE`). The **published `GhosttyKit.xcframework`
contains compiled Ghostty**, which is MIT-licensed by upstream; its notice travels with the binary
(`LICENSE-ghostty`). This repo redistributes Ghostty's compiled bytes under that license.
