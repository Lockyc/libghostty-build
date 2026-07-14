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
  sha256 + attest → publish release `ghostty-<short-sha>` with **two** assets (xcframework +
  resources). Single job on `macos-15`.

## Load-bearing invariants (don't regress)

- **Publish the runtime resources, not just the library — the library alone is an incomplete
  libghostty.** `GhosttyResources.zip` (`terminfo/` + `ghostty/shell-integration/`, rooted so it
  unpacks straight into an embedder's `Contents/Resources`) is a **required** second asset. libghostty
  locates itself at surface spawn by climbing from its executable for the sentinel
  `Contents/Resources/terminfo/78/xterm-ghostty` (`src/os/resourcesdir.zig`); miss it and
  `Subprocess.init` silently falls back to `TERM=xterm-256color` (`src/termio/Exec.zig`). The terminal
  then advertises no `Sync` capability, so tmux stops bracketing its redraws in DEC 2026 — which is
  the *one* thing that makes libghostty pause rendering — so it renders half-drawn frames, and an
  unfocused surface (which draws its hollow cursor on **every** frame, bypassing the blink gate —
  `src/renderer/cursor.zig`) flickers that cursor at whatever mid-repaint position it sampled. That
  was warden's "cursor flashes around the screen when the window isn't focused" bug. We don't *build*
  these: Ghostty's xcframework graph **always installs resources** (build.zig — its Xcode project
  references them), so they already sit in `zig-out/share`; the script only collects them. The staging
  step hard-fails when the sentinel is missing, precisely because the runtime failure is silent.
- **Ship `terminfo` + `shell-integration` only — themes/docs are deliberately excluded.** Both are
  gated off by default (`emit_themes`/`emit_docs`) and warden exposes no ghostty theme config, so
  they'd be dead weight in every clone that vendors this. Don't add `-Demit-themes` to "be complete".
- **Let Ghostty *compile* its own xcframework — don't hand-assemble the library.** The build calls
  `zig build -Demit-xcframework=true` (with `-Dxcframework-target=universal`, the default), which
  cross-compiles both macOS arches and assembles the universal libghostty. The earlier hand-rolled
  path (per-arch `libghostty.a` via `-Dapp-runtime=none` + `lipo`) **fails**: on Darwin,
  `-Dapp-runtime=none` does not emit `libghostty.a` without triggering the xcframework graph anyway.
  Use the native emit; don't reintroduce per-arch assembly. (We *do* run one
  `xcodebuild -create-xcframework` afterward — but only to *repackage*, see next point.)
- **Repackage macOS-only, library renamed `libghostty.a` (bytes untouched).** Ghostty's native
  xcframework ships the macOS archive as **`ghostty-internal.a`** (renamed from `libghostty.a` since
  v1.3.1) and bundles **iOS slices** warden never uses (~130MB). warden's `build.rs` does
  `link-lib=static=ghostty` → it needs a file literally named `libghostty.a` (the `lib` prefix is not
  optional), macOS only. So after Ghostty builds, the script extracts the macOS-universal archive,
  names it `libghostty.a`, and rebuilds a macOS-only xcframework around it. This renames/prunes the
  *wrapper* only — the compiled libghostty bytes are exactly upstream's, so the "unmodified upstream"
  claim holds. The script finds the `.a` by glob (not by the `ghostty-internal.a` name) so a future
  upstream rename doesn't break it.
- **Strip debug symbols (`strip -S`).** Zig's ReleaseFast archive carries ~220MB of DWARF (~280MB →
  ~48MB stripped). `strip -S` removes debug symbols only; the exported `ghostty_*` C API is untouched,
  so static linking is unaffected. Without this the vendored binary is 7× larger for no benefit —
  warden never debugs into libghostty. Don't drop the strip to "keep symbols"; reproduce a
  symbolicated build from the pinned commit if ever needed.
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
