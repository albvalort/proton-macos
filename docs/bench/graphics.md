# Graphics (milestone 3): results

Machine: MacBook M2, macOS 27.0.1, Wine 11 x86_64 (Rosetta), MoltenVK 1.4.2, DXVK-macOS 1.10.3. Date: 2026-10-12.
Measurement: `scripts/bench.sh` (Metal HUD in the system log, or Wine's `+fps` trace), 30 s after a warm-up, in
the main menu (repeatable scene). Raw data: [results.csv](results.csv).

| Game | API | Backend (`PROTON_MAC_GFX`) | Path | Average fps | Min. (1 s) |
|---|---|---|---|---|---|
| Downwell (360740) | D3D11 | `dxvk` | DXVK-macOS → MoltenVK → Metal | 60.0 | 60.0 |
| Downwell (360740) | D3D11 | `wined3d` | wined3d → OpenGL 4.1 | 59.7 | 58.3 |
| ANIMAL WELL (813230) | D3D12 | `dxvk` (*) | Wine's vkd3d → MoltenVK → Metal | 60.0 | 60.0 |
| ANIMAL WELL (813230) | D3D12 | `d3dmetal` | D3DMetal (GPTK 4.0 beta 2) → Metal | 60.0 | 60.0 |

(*) DXVK-macOS only replaces D3D10/11; D3D12 uses Wine's `d3d12` (vkd3d) with every backend except
`d3dmetal`.

Notes:

- The 60 fps figures are capped by vsync (60 Hz display). They show that it works, not a performance
  comparison. Real profiling belongs to milestone 8.
- DXVK: D3D11 feature level 11_0 on "Apple M2". vkd3d warns that geometry shaders, stream output, cull
  distance and depth clip are missing in MoltenVK. It affects some DX12 games, not ANIMAL WELL.
- The Metal HUD may stop logging if the game recreates its swap chain (it happened to Downwell with DXVK).
  That is why `bench.sh` also collects Wine's `+fps` trace and keeps the source with more samples.
- D3DMetal visually validated by the user with ANIMAL WELL (fullscreen). Comparing D3DMetal and vkd3d
  performance needs a scene without vsync or a heavier one (milestone 8).
- Downwell (DXVK) launched and played by the user from the Steam library.
