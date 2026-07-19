# gpui (MGVS fork)

A fork of [**gpui**](https://github.com/zed-industries/zed/tree/main/crates/gpui) —
the GPU-accelerated UI framework developed by Zed Industries — pinned at upstream
revision [`c545fb67`](https://github.com/zed-industries/zed/commit/c545fb67d0ce13e335bff76f7c08986000333f2c)
and carrying MGVS modifications for **zero-copy native-texture presentation**.

## What is modified

The changes add a single-plane **`32BGRA` external-texture present path** to the
macOS/Metal backend so a client can hand gpui an already-rendered `IOSurface`
(wrapped as a `CVPixelBuffer`) instead of round-tripping the frame through the CPU
atlas each interaction frame. This is what NeoCAD's GPUI shell uses to present its
offscreen 2D/3D `wgpu` canvas zero-copy.

Modified files (vs upstream `c545fb67`):

- `crates/gpui_macos/src/metal_renderer.rs` — `draw_surfaces` BGRA branch + RGBA `surface_fragment`
- `crates/gpui_macos/src/metal_atlas.rs`
- `crates/gpui_macos/src/shaders.metal`

## Layout

A self-contained Cargo workspace (`default-members = ["crates/gpui"]`). Consume it
as a git dependency:

```toml
gpui          = { git = "https://github.com/mgvs/gpui", branch = "main" }
gpui_platform = { git = "https://github.com/mgvs/gpui", branch = "main", features = ["font-kit", "runtime_shaders"] }
```

Pin an exact `rev = "…"` for reproducible builds. All `gpui_*` crates resolve from
this one repository (workspace dependencies), so no `[patch]` juggling is needed on
the consumer side.

## Building

The macOS backend (`gpui_macos`) compiles and validates **only on macOS** (Metal +
native Apple deps). Linux/CI hosts cannot cross-compile it.

## License

Licensed under the **Apache License 2.0**, inherited from upstream gpui (see the
per-crate `LICENSE-APACHE` files and `NOTICE`).
