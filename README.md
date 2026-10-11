# Proton-macOS (working title)

Run Windows games from your Steam library on Apple Silicon Macs, using a macOS port of
[Proton](https://github.com/ValveSoftware/Proton) — the same compatibility tool Valve ships on Linux
and the Steam Deck.

> **Status: early research / pre-alpha.** Nothing here runs games yet. See [docs/STATUS.md](docs/STATUS.md).

> **Not affiliated with Valve or Apple.** "Steam" and "Proton" are trademarks of Valve Corporation.

## Goal

Keep the **same contract as Proton on Linux** (the `proton` script, `PROTON_*` variables,
`toolmanifest.vdf`, `compatibilitytools.d`), so that the work is easy to rebase on upstream and could
one day be adopted by Valve as native Steam Play support on macOS.

## Architecture

```
Windows game (.exe, x86/x86_64)
 └─ Wine (Valve's fork, `macos` branch) — x86_64 under Rosetta 2, winemac.drv, new WoW64
     ├─ Graphics: D3DMetal (from the user's own GPTK) | DXVK → MoltenVK | wined3d   (PROTON_MAC_GFX)
     ├─ Sync: msync (Mach semaphores)                                             (PROTON_NO_MSYNC=1)
     └─ lsteamclient → steamclient.dylib of the running Steam client (loaded in-process, x86_64 slice)
 └─ `proton` script (Python) — run / waitforexitandrun / getcompatpath, as on Linux
Steam client
 └─ compatibilitytools.d/<tool>  (from_oslist windows → to_oslist macos)
```

Key research results (details in [docs/research/](docs/research/00-findings.md)):

- `steamclient.dylib` is universal (`x86_64 arm64`), so Wine under Rosetta can load it in-process.
- The macOS Steam client already contains the full Steam Play compatibility manager. It is gated by a
  single `oslist == "linux"` check. With that check flipped at runtime, Steam on macOS registers a
  `windows → macos` tool, downloads Windows depots and launches the tool with the same
  `waitforexitandrun` + `STEAM_COMPAT_*` contract as on Linux.

## Graphics and Apple software

This project **never distributes** any part of Apple's Game Porting Toolkit (D3DMetal, MetalFX).
If you install GPTK yourself from Apple, Proton-macOS can detect it and use it. Otherwise it falls
back to open-source components (DXVK on MoltenVK, or wined3d). Using GPTK is subject to Apple's
license terms.

## Repository layout

| Path | Contents |
|---|---|
| `external/proton`, `external/wine` | Forks of Valve's Proton and Wine (`macos` branch), as submodules |
| `scripts/` | `doctor.sh` (environment check), build scripts |
| `tools/re/` | Small reverse-engineering helpers used for the research |
| `docs/research/` | Findings, with evidence and confidence levels |
| `docs/adr/` | Architecture decision records |
| `docs/patches/` | Every patch we carry against upstream, and why |

## Getting started (developers)

```sh
git clone --recurse-submodules --shallow-submodules https://github.com/albvalort/proton-macos.git
cd proton-macos
scripts/doctor.sh
```

Requirements: Apple Silicon Mac, Rosetta 2, Xcode Command Line Tools, Homebrew (arm64),
[llvm-mingw](https://github.com/mstorsjo/llvm-mingw), Steam for Mac.

## License

Our own code is BSD-3-Clause ([LICENSE](LICENSE)). Wine is LGPL-2.1-or-later; other components keep
their own licenses ([NOTICE](NOTICE)).
