# libghostty-build — agent orientation

## What this repo is

A **build-tooling** repo. It compiles [Ghostty](https://github.com/ghostty-org/ghostty)'s embedding
library from a pinned, **unmodified** upstream commit and publishes it as a release asset that
[warden](https://github.com/lockyc/warden) vendors. It ships no library source of its own — the
deliverable is the CI-built artifact.

Today that artifact is the macOS `GhosttyKit.xcframework`. The repo name is platform-neutral
deliberately: a future libghostty build for another platform belongs here too, not in a renamed repo.
warden is macOS-first, so macOS is the only target now.

## Current state

Minimal by design (baseline deferred): `GHOSTTY_REF`, `scripts/build-xcframework.sh`, the build
workflow, README, this file. **Not yet added** (follow-ups): `catalog.toml`, a docaudit pre-push
gate, a `justfile`, a CI-lint workflow, and offsite Forgejo mirror registration — add via the
`project-standards` skill once the pipeline is proven green.

## Layout

- **`GHOSTTY_REF`** — single source of truth: the exact Ghostty commit SHA to build. Bumping the
  Ghostty version = edit this file + re-run the workflow. Never hard-code the SHA anywhere else.
- **`scripts/build-xcframework.sh`** — clones nothing; takes a Ghostty source tree + output dir and
  runs Ghostty's **own** native xcframework build, then stages the result. Applies no patches — we
  build unmodified upstream on purpose.
- **`.github/workflows/build.yml`** — resolve ref → SHA → clone unmodified Ghostty → build → zip +
  sha256 + attest → publish release `ghostty-<short-sha>`. Single job on `macos-15`.

## Load-bearing invariants (don't regress)

- **Let Ghostty build its own xcframework — don't hand-assemble.** The build calls
  `zig build -Demit-xcframework=true` (with `-Dxcframework-target=universal`, the default), which
  cross-compiles both arches and assembles `macos/GhosttyKit.xcframework` with headers included. The
  earlier hand-rolled path (per-arch `libghostty.a` via `-Dapp-runtime=none` + `lipo` +
  `xcodebuild -create-xcframework`) **fails**: on Darwin, `-Dapp-runtime=none` does not emit
  `libghostty.a` without triggering the xcframework graph anyway. Use the native emit; don't
  reintroduce the manual assembly.
- **Build on `macos-15`, not `macos-26`.** Ghostty pins **Zig 0.15.2**, which could not link a
  macOS 26 SDK. Sequoia's 15.x SDK links cleanly. The runner-OS choice *is* the unblock — the whole
  reason a local build failed but CI works. If you must move runners, that SDK-link constraint is why
  this one was chosen.
- **Zig is pinned to 0.15.2.** Ghostty's `build.zig.zon` `minimum_zig_version` is 0.15.2; Homebrew's
  0.16.0 won't build it. Keep `setup-zig` on 0.15.2, bumping only when upstream Ghostty does.
- **Universal (arm64 + x86_64) slice.** warden's `build.rs` hard-codes the slice path
  `macos-arm64_x86_64`. The default `xcframework-target=universal` produces exactly that; a `native`
  build would produce `macos-arm64` and break warden's link path. warden runs aarch64 only, but the
  *slice name* is what forces universal here.
- **No patches / no fork.** We build unmodified upstream — no `apply-patches` step (that was
  libghostty-spm's iOS-only patching, which we skip deliberately: unmodified is a feature, and it's
  what lets warden's `PROVENANCE.md` claim a known-upstream binary).

## Build flags that broke on a version bump (footgun)

Flags cribbed from an older Ghostty can vanish. The first attempt used `-Dinspector` and
`-Dcustom-shaders` (valid at v1.3.1, **removed** by `main`); zig rejects unknown `-D` options before
compiling. When bumping `GHOSTTY_REF` across a big jump and the build dies at option parsing, diff the
flags against `src/build/Config.zig` at the new SHA rather than assuming a deeper failure.

## Known deviation from the libghostty-spm reference

libghostty-spm appends a `__libcpp_verbose_abort` compat shim (for consumers on macOS < 13.3). Our
native-xcframework build does not. warden targets modern macOS, where the system libc++ exports the
symbol, so this is fine. If a warden link or launch ever fails on `std::__1::__libcpp_verbose_abort`,
that's the lever — reintroduce the shim in the build script.
