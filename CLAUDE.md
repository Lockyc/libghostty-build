# libghostty-macos — agent orientation

## What this repo is

A **build-tooling** repo. It compiles [Ghostty](https://github.com/ghostty-org/ghostty)'s
`GhosttyKit` embedding framework from a pinned, **unmodified** upstream commit and publishes it as a
release asset that [warden](https://github.com/lockyc/warden) vendors. It ships no library source of
its own — the deliverable is the CI-built `GhosttyKit.xcframework.zip`.

## Current state

Minimal by design (baseline deferred): `GHOSTTY_REF`, `scripts/build-target.sh`, the build workflow,
README, this file. **Not yet added** (follow-ups): `catalog.toml`, a docaudit pre-push gate, a
`justfile`, a CI-lint workflow, and offsite Forgejo mirror registration — add via the
`project-standards` skill once the pipeline is proven green.

## Layout

- **`GHOSTTY_REF`** — single source of truth: the exact Ghostty commit SHA to build. Bumping the
  Ghostty version = edit this file + re-run the workflow. Never hard-code the SHA anywhere else.
- **`scripts/build-target.sh`** — builds libghostty for one arch (`aarch64-macos` / `x86_64-macos`).
  Mirrors the known-good libghostty-spm flags but **applies no patches** — we build unmodified
  upstream macOS Ghostty on purpose.
- **`.github/workflows/build.yml`** — resolve ref → build both arches (matrix) → `lipo` universal →
  `xcodebuild -create-xcframework` → zip + sha256 + attest → publish release `ghostty-<short-sha>`.

## Load-bearing invariants (don't regress)

- **Build on `macos-15`, not `macos-26`.** Ghostty pins **Zig 0.15.2**, which could not link a
  macOS 26 SDK. Sequoia's 15.x SDK links cleanly. The runner-OS choice *is* the unblock — the whole
  reason a local build failed but CI works. If you must move runners, that SDK-link constraint is why
  this one was chosen.
- **Zig is pinned to 0.15.2.** Ghostty's `build.zig.zon` `minimum_zig_version` is 0.15.2; Homebrew's
  0.16.0 won't build it. Keep `setup-zig` on 0.15.2, bumping only when upstream Ghostty does.
- **Universal (arm64 + x86_64), not aarch64-only.** warden's `build.rs` hard-codes the slice path
  `macos-arm64_x86_64`. `xcodebuild` names the slice from the archs present, so both must be lipo'd in
  or the slice is `macos-arm64` and warden's link path breaks. warden runs aarch64 only, but the
  *slice name* is what forces universal here.
- **No patches / no fork.** We build unmodified upstream. Do not add an `apply-patches` step (that was
  libghostty-spm's iOS-only patching, which we skip deliberately — unmodified is a feature, and it's
  what lets warden's `PROVENANCE.md` claim a known-upstream binary).

## Known deviation from the vendored reference

libghostty-spm appends a `__libcpp_verbose_abort` compat shim (for consumers on macOS < 13.3). We
omit it — warden targets modern macOS, where the system libc++ exports the symbol. If a warden link
or launch ever fails on `std::__1::__libcpp_verbose_abort`, re-introduce the shim in
`build-target.sh` (compile a tiny weak-symbol object with `zig cc` and `libtool -static` it into the
archive, as libghostty-spm does).

## The one unproven assumption

That Zig 0.15.2 links `macos-15`'s SDK cleanly. All signals say yes; the first workflow run is the
test. If it fails there, try `macos-14`, then investigate SDK flags — don't reach for a fork.
