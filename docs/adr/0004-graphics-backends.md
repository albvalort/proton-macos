# ADR 0004: Graphics backends on macOS

- Status: accepted (all three backends work; D3DMetal validated with GPTK 4.0 beta 2)
- Date: 2026-10-11

## Context

On Linux, Proton translates D3D9/10/11 with DXVK and D3D12 with vkd3d-proton, both on Vulkan. On macOS there
are four options:

| Option | APIs covered | Requirement | Problem |
|---|---|---|---|
| wined3d (Wine's) | D3D1–11, partial D3D12 with vkd3d | OpenGL 4.1 (or Vulkan) | Slow, and poor D3D11 coverage on GL 4.1 |
| DXVK on MoltenVK | D3D10/11 | MoltenVK (universal, Apache-2.0) | DXVK 2.x needs extensions MoltenVK lacks; Gcenx's macOS fork (DXVK 1.10.3, zlib) must be used, as CrossOver does |
| DXVK 2.x / vkd3d-proton on **KosmicKrisp** | D3D9–12 | KosmicKrisp (Mesa on Metal 4, Vulkan 1.4 conformant and production ready according to [LunarG, Oct 2026](https://www.lunarg.com/the-state-of-vulkan-on-apple-oct-2026/)) | **arm64 only**: it cannot be loaded into an x86_64 process under Rosetta, which our Wine is |
| D3DMetal (Apple's GPTK) | D3D11/12 | The user installs GPTK | Cannot be redistributed. The license limits its use to evaluating ports. The ABI of its unix modules must match our Wine version |

## Decision

- `PROTON_MAC_GFX=dxvk|d3dmetal|wined3d` in the `proton` script. Default: **dxvk** if it is packaged;
  otherwise wined3d. `d3dmetal` is always opt-in and only works if GPTK is found (`PROTON_MAC_GPTK`,
  `~/Library/Application Support/proton-macos/gptk/*/redist/lib` or the mounted evaluation environment). Its
  modules are symlinked into `<compatdata>/gptk/` and searched before Wine's (`WINEDLLPATH_PREPEND`). Nothing
  from Apple is copied. Wine integration ported from CrossOver: see `docs/patches/wine.md`. x86_64 only (GPTK
  ships no 32-bit modules).
- DXVK-macOS 1.10.3 (Gcenx, zlib) provides `d3d11`/`d3d10core`. `dxgi`, `d3d9` and `d3d12` are Wine's, the
  latter with vkd3d on winevulkan → MoltenVK.
- Wine is built with Vulkan against MoltenVK 1.4.2 (official universal binary, packaged with Wine).
- **KosmicKrisp:** not integrated for now (no selector implemented), because it cannot work with x86_64 Wine.
  It would need Wine's unix side in arm64, with x86 PE code translated by another mechanism, or out-of-process
  rendering. To be revisited if LunarG publishes an x86_64 slice.
- OpenGL games go through Apple's OpenGL 4.1 (Metal-backed). `WINE_GL_VENDOR_REPORT_AMD=1` reports another
  vendor for engines that switch features off on "Apple" GPUs (Godot 3 disables its depth prepass and
  opaque-prepass materials disappear).

## Consequences

- DX12 without GPTK depends on vkd3d (not vkd3d-proton) on MoltenVK: limited compatibility.
- For serious DX12, D3DMetal is today the only route, and it is up to the user and Apple's license.
- Per-backend benchmarks in `docs/bench/` (milestone 3).
