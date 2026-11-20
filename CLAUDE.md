---
type: architecture
links:
  - rel: see-also
    to: README.md
---

# libghostty-build — agent orientation

## What this repo is

A **build-tooling** repo. It compiles [Ghostty](https://github.com/ghostty-org/ghostty)'s embedding
library from a pinned, **unmodified** upstream commit and publishes it as a release asset that
[warden](https://github.com/lockyc/warden) vendors. It ships no library source of its own — the
deliverable is the CI-built artifact.

Today that artifact is three macOS assets: `GhosttyKit.xcframework`, its runtime resources, and
libghostty-vt (the standalone VT library). The repo name is platform-neutral
deliberately: a future libghostty build for another platform belongs here too, not in a renamed repo.
warden is macOS-first, so macOS is the only target now.

## Current state

Minimal by design: `GHOSTTY_REF`, `scripts/build-xcframework.sh`, `scripts/build-vt.sh`, the two workflows, the
`mycelium.toml` sidecar, README, this file, and the docgraph pre-push gate (`.githooks/pre-push`;
`git config core.hooksPath .githooks` wires it per clone). A `justfile` is deliberately absent and
exempt in the sidecar, and there is no CI-lint workflow: the build is CI-only (see the `macos-15` invariant
below), so there is no local recipe to wrap.

## Layout

- **`GHOSTTY_REF`** — single source of truth: the Ghostty ref to build (a stable tag or a commit
  SHA). The workflow resolves it to a SHA, and the release is tagged by the resolved short SHA.
  Bumping Ghostty = edit this file + re-run the workflow. Never hard-code the ref anywhere else.
- **`scripts/build-xcframework.sh`** — clones nothing; takes a Ghostty source tree + output dir and
  runs Ghostty's **own** native xcframework build, then stages the result. Applies no patches — we
  build unmodified upstream on purpose.
- **`scripts/build-vt.sh`** — builds libghostty-vt (`-Demit-lib-vt=true`, which installs one target per
  build) for aarch64 and x86_64, `lipo`s them into a universal `libghostty-vt.a`, strips debug symbols,
  and stages it with `include/ghostty/vt.h` + `vt/`. Hard-fails if the snapshot/formatter entry points
  warden-relay links are missing. Unpatched, like the xcframework build.
- **`.github/workflows/build.yml`** — resolve ref → SHA → clone unmodified Ghostty → build → zip +
  sha256 + attest → publish release `ghostty-<short-sha>` with **three** assets (xcframework +
  resources + libghostty-vt). Single job on `macos-15`. The `vt_only` input builds just libghostty-vt and uploads it to the ref's existing release, leaving the other assets' bytes alone (a full run is not reproducible and clobbers them). Manual (`workflow_dispatch`) — bumping `GHOSTTY_REF` and
  re-running *is* the release. The `ghostty_ref` input builds another ref without moving the pin;
  that build publishes as a prerelease, so warden (which vendors the latest release) never picks it
  up. `vt_only` with `ghostty_ref` left empty adds libghostty-vt to the pinned ref's release.
- **`.github/workflows/ghostty-tag-watch.yml`** — weekly (the workflow's `schedule` cron) +
  dispatchable. Opens
  an issue when upstream publishes a new stable **tag** on either release line — Ghostty's
  `vX.Y.Z` (the surface) or libghostty-vt's `vt-X.Y.Z` (what warden-relay links) — so a
  `GHOSTTY_REF` bump onto a vetted release gets considered. It watches tags, not releases: Ghostty ships stable versions as git tags
  and only the nightly "tip" is a GitHub Release, so `releases/latest` 404s.
  - **It commits and pushes to `main` on its own.** After filing the issue it writes the new tag to
    the marker and pushes as `github-actions[bot]`. A lone `chore: mark Ghostty vX as seen` commit
    on `main` is this job, not stray drift — don't revert it as unexplained.
  - **Its first step re-enables itself via the Actions API** (`actions: write`). GitHub disables a
    scheduled workflow after 60 days without repo activity, and a successful run with no new tag
    commits nothing — so without the keepalive the watch goes silent in a quiet stretch. Don't drop
    the step or move it after the check.
- **`.github/ghostty-latest-seen`** + **`.github/libghostty-vt-latest-seen`** — the watcher's
  entire state: per release line, the last upstream stable tag it filed an issue for. Committed on purpose, and what makes the watch one-issue-per-tag rather than
  one-per-run. Editing it by hand re-arms (or suppresses) the next notification.

## Load-bearing invariants (don't regress)

- **Publish the runtime resources, not just the library — the library alone is an incomplete
  libghostty.** `GhosttyResources.zip` (`terminfo/` + `ghostty/shell-integration/`, rooted so it
  unpacks straight into an embedder's `Contents/Resources`) is a **required** second asset; why, and
  why it is collected rather than built, is at the resources section of
  `scripts/build-xcframework.sh`. The staging step hard-fails when the sentinel is missing, because
  the runtime failure is silent.
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
- **Repackage macOS-only, library renamed `libghostty.a` (bytes untouched).** The reasons are in
  `scripts/build-xcframework.sh`'s header. The script finds the `.a` by glob, not by upstream's
  current name, so an upstream rename doesn't break it.
- **Strip debug symbols (`strip -S`).** The reason and sizes are at the strip in
  `scripts/build-xcframework.sh`. Don't drop it to "keep symbols"; reproduce a symbolicated build
  from the pinned commit if ever needed.
- **Build on `macos-15`.** Sequoia's 15.x SDK is the one this build is verified against; Zig 0.15.2
  could not link the macOS 26 SDK. Whether 0.17.0 can is untried here. Upstream's own macOS CI runs
  on Tahoe, so a `macos-26` run (or a local build on macOS 26) is the test that would
  lift the CI-only constraint.
- **The Zig version is read from Ghostty's `build.zig.zon`** (`minimum_zig_version` at the SHA being
  built, build.yml's "Read Ghostty's minimum Zig version" step), never pinned here: Zig is not
  backward-compatible across minors, and upstream's declaration is the one that matches its code.
- **Universal (arm64 + x86_64) slice.** warden's `build.rs` hard-codes the slice path
  `macos-arm64_x86_64`. The default `xcframework-target=universal` produces exactly that; a `native`
  build would produce `macos-arm64` and break warden's link path. warden runs aarch64 only, but the
  *slice name* is what forces universal here.
- **No patches / no fork.** We build unmodified upstream — no `apply-patches` step (that was
  libghostty-spm's iOS-only patching, which we skip deliberately: unmodified is a feature, and it's
  what lets warden's `PROVENANCE.md` claim a known-upstream binary).

## Build flags that broke on a version bump (footgun)

Flags valid at one Ghostty version can be gone at the next, and zig rejects an unknown `-D` option
before compiling. When a `GHOSTTY_REF` bump dies at option parsing, diff the flags against
`src/build/Config.zig` at the new SHA rather than assuming a deeper failure.

## Known deviation from the libghostty-spm reference

libghostty-spm appends a `__libcpp_verbose_abort` compat shim (for consumers on macOS < 13.3). Our
native-xcframework build does not. warden targets modern macOS, where the system libc++ exports the
symbol, so this is fine. If a warden link or launch ever fails on `std::__1::__libcpp_verbose_abort`,
that's the lever — reintroduce the shim in the build script.
