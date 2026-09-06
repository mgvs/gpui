# gpui (MGVS fork)

A fork of [**gpui**](https://github.com/zed-industries/zed/tree/main/crates/gpui) —
the GPU-accelerated UI framework developed by Zed Industries — carrying MGVS
modifications for **zero-copy native-texture presentation**. This is what
NeoCAD's GPUI shell uses to present its offscreen 2D/3D `wgpu` canvas without
round-tripping frames through the CPU atlas.

Unlike a snapshot import, this repository keeps the **real upstream history**:
5738 commits on `main` (5964 on `upstream`) reaching back to gpui's
first one (`Start rebuilding with a cleanly-separated UI framework`, 2021-02-20),
each with its original author, date and message. `git log`, `git blame` and
`git bisect` work across upstream code, and taking a newer upstream is a merge
rather than a re-import.

## Branches

| branch     | contents |
| ---------- | -------- |
| `upstream` | filtered upstream history only — no MGVS changes. Advanced by `scripts/sync-upstream.sh`. |
| `main`     | `upstream` at the base revision below, plus the four MGVS commits. **Pin this one.** |

## What is in the tree

A self-contained Cargo workspace (`default-members = ["crates/gpui"]`) holding
gpui and the crates it needs: `collections`, `gpui`, `gpui_linux`, `gpui_macos`,
`gpui_macros`, `gpui_platform`, `gpui_shared_string`, `gpui_util`, `gpui_web`,
`gpui_wgpu`, `gpui_windows`, `http_client`, `http_client_tls`, `media`,
`refineable`, `reqwest_client`, `scheduler`, `sum_tree`, `util`, `util_macros`,
`zlog`, `ztracing`, `ztracing_macro`, plus `assets/fonts` and `tooling/perf`. The authoritative list is
[`scripts/upstream-paths.txt`](scripts/upstream-paths.txt).

Three of those — `util`, `reqwest_client` and `http_client_tls` — are carried for
Cargo's sake rather than gpui's. `http_client` declares `util` behind its
`github-download` feature and `gpui` declares `reqwest_client` as a
dev-dependency (which in turn wants `http_client_tls`). Cargo resolves a path
dependency whether or not the feature is enabled and whether or not it is a
dev-dependency, so **without** those three the workspace manifest cannot be
loaded at all: `cargo build`, `cargo check` and `cargo metadata` all fail inside
a checkout, as they did in the previous snapshot import of this fork. They cost
consumers nothing — a git dependency never resolves another package's
dev-dependencies or unactivated optional ones.

The root `Cargo.toml` is upstream's, with `members` pruned to the crates that
actually exist here and `default-members` pointed at `crates/gpui`; everything
else in it, `[workspace.dependencies]` included, is upstream's own text. See
[`scripts/prune-workspace.py`](scripts/prune-workspace.py).

## The MGVS delta

Four commits on top of `upstream`, the code change deliberately last so it
rebases and cherry-picks on its own:

1. `chore(workspace)` — prune the workspace manifest (above).
2. `docs` — this README, `NOTICE`, `.gitignore`.
3. `build` — the upstream sync tooling under `scripts/`.
4. `feat(gpui_macos)` — **the actual patch**: a single-plane `32BGRA`
   external-texture present path in the macOS/Metal backend, so a client can
   hand gpui an already-rendered `IOSurface` (wrapped as a `CVPixelBuffer`)
   instead of the biplanar NV12 the surface path assumed. Two files:
   * `crates/gpui_macos/src/metal_renderer.rs` — per-surface pipeline selection
     by pixel format, plus the `surfaces_rgba` pipeline state;
   * `crates/gpui_macos/src/shaders.metal` — the `surface_fragment_rgba`
     passthrough fragment shader.

## Revisions

| | fork | upstream (`zed-industries/zed`) |
| --- | --- | --- |
| `main` base | [`bc70bb583d05e2059de3280a47fa3690e387289d`](../../commit/bc70bb583d05e2059de3280a47fa3690e387289d) | [`4b7369481dcf36f22ff8f813d411e1d296aebe57`](https://github.com/zed-industries/zed/commit/4b7369481dcf36f22ff8f813d411e1d296aebe57) |
| `upstream` tip | [`4fe56888a4cf5e7b74ffa4f654dfd597822596f1`](../../commit/4fe56888a4cf5e7b74ffa4f654dfd597822596f1) | [`9bda6b4e0342f22680bc1e7fcd847f4697c48874`](https://github.com/zed-industries/zed/commit/9bda6b4e0342f22680bc1e7fcd847f4697c48874) |

The base revision is the counterpart of upstream
[`c545fb67`](https://github.com/zed-industries/zed/commit/c545fb67d0ce13e335bff76f7c08986000333f2c),
which this fork was originally pinned at: the 14 upstream commits between
`4b7369481dcf36f22ff8f813d411e1d296aebe57` and `c545fb67` touch none of the paths carried here, so the two
trees are identical over every file in this repository. `main` therefore builds
exactly the code the pre-history import did — crate sources are byte-identical to
the previous `main`.

`upstream` is ahead of `main` and merges when you want it — see below.

## Syncing with upstream

Because this is a path-filtered extraction rather than a whole-repo fork, a sync
re-derives the filtered history and appends the new commits:

```sh
pip install git-filter-repo          # once
scripts/sync-upstream.sh             # advance the `upstream` branch
git checkout main && git merge upstream
```

or `scripts/sync-upstream.sh --merge` to do both, which also re-prunes
`Cargo.toml` for you. Expect the merge to conflict only where upstream touched
`crates/gpui_macos/src/metal_renderer.rs` or `shaders.metal` — the two files the
MGVS patch owns.

The extraction is reproducible: re-filtering a newer upstream reproduces every
commit already published here bit-for-bit and adds the new ones on top. Two
inputs are load-bearing and the script pins both — the path list, and
`--preserve-commit-hashes` (without it git-filter-repo rewrites commit SHAs
quoted inside commit *messages*, and the result depends on which refs were in the
clone). `sync-upstream.sh` verifies the property instead of assuming it: it
refuses to move `upstream` unless the published tip is an ancestor of what came
back out.

**Fork SHAs are not upstream SHAs.** Rewritten history means new commit ids, so a
patch cannot be pushed to `zed-industries/zed` from here — export it and apply it
to a real Zed checkout.

## Consuming

```toml
gpui          = { git = "https://github.com/mgvs/gpui", rev = "…" }
gpui_platform = { git = "https://github.com/mgvs/gpui", rev = "…", features = ["font-kit", "runtime_shaders"] }
```

Pin an exact `rev` on `main` for reproducible builds. All `gpui_*` crates resolve
from this one repository (workspace dependencies), so no `[patch]` juggling is
needed on the consumer side.

Superseded pins keep working: the pre-history squashed import is kept on the
branch [`legacy/squashed-import-915a9af`](../../tree/legacy/squashed-import-915a9af),
so `rev = "915a9af15612f1dbbf8385f4b8fbaa4833bf3130"` still resolves. It shares no
history with `main` and is frozen — new work goes on `main`.

## Building

The macOS backend (`gpui_macos`) compiles and validates **only on macOS** (Metal +
native Apple deps). Linux/CI hosts cannot cross-compile it.

## License

Licensed under the **Apache License 2.0**, inherited from upstream gpui (see the
per-crate `LICENSE-APACHE` files and `NOTICE`). `zlog`, `ztracing` and
`ztracing_macro` carry upstream's dual `LICENSE-APACHE` / `LICENSE-GPL` files;
consult them before shipping.
