# Proton-macOS (working title)

Run Windows games from your Steam library on Apple Silicon Macs, using a macOS port of
[Proton](https://github.com/ValveSoftware/Proton) — the same compatibility tool Valve ships on Linux
and the Steam Deck.

> **Status: alpha.** Several Windows games run and play (Downwell, ANIMAL WELL, Minimalism, Lingo), with
> the Steam API (achievements) working. Expect rough edges. Per-game notes live in [compat/](compat) and
> progress in [docs/STATUS.md](docs/STATUS.md).

> **Not affiliated with Valve or Apple.** "Steam" and "Proton" are trademarks of Valve Corporation.

## Requirements

- A Mac with Apple Silicon (M1 or later). Builds target macOS 11+, but only macOS 27 has been tested.
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`
- Xcode Command Line Tools (for `python3`, used by the `proton` script): `xcode-select --install`
- Steam for Mac, installed and opened at least once.
- The Steam mobile app, to log in with a QR code when downloading games.

## Install

1. Download `proton-macos-<version>.tar.xz` from the
   [releases page](https://github.com/albvalort/proton-macos/releases) (optionally check it against the
   `.sha256` file).
2. Extract it and run the installer:

   ```sh
   tar -xJf proton-macos-<version>.tar.xz
   cd proton-macos-<version>
   ./install.sh
   ```

   It needs no `sudo`. It copies the compatibility tool into
   `~/Library/Application Support/Steam/compatibilitytools.d/proton_macos`, downloads
   [DepotDownloader](https://github.com/SteamRE/DepotDownloader) into `~/.local/opt/depotdownloader`, and
   links the `pmac` launcher into `~/.local/bin` (add it to your `PATH` if the installer says so).

To update, run the new version's `install.sh`. To uninstall, delete
`~/Library/Application Support/Steam/compatibilitytools.d/proton_macos`, `~/.local/opt/depotdownloader`,
`~/.local/bin/pmac` and, if you want to drop game prefixes and downloads,
`~/Library/Application Support/proton-macos`.

## Play a game

The Mac Steam client does not offer Windows versions of games, so `pmac` does the downloading and
launching. Keep Steam open while playing: games talk to it for achievements, overlay status and DRM.

```sh
pmac login              # once: scan the QR code with the Steam mobile app (no password is ever asked)
pmac list               # games in your library without a macOS version (--all for every game)
pmac install 1814170    # download the Windows version (here: Lingo)
pmac run 1814170        # play
```

To launch it from Steam instead, quit Steam and run `pmac shortcut <appid>`: the game appears in your
library (with its official artwork) and **Play** starts it through Proton-macOS.

Useful options, as environment variables for `pmac run` or in `compat/<appid>.yaml`:

| Variable | Effect |
|---|---|
| `PROTON_MAC_GFX=dxvk` (default) | Direct3D 9–11 through DXVK on MoltenVK; Direct3D 12 through vkd3d |
| `PROTON_MAC_GFX=d3dmetal` | Apple's D3DMetal, **only if you installed Apple's Game Porting Toolkit yourself** (see below) |
| `PROTON_MAC_GFX=wined3d` | Wine's own OpenGL-based Direct3D |
| `PROTON_NO_MSYNC=1` | Disable msync (fast synchronisation primitives) |
| `WINE_GL_VENDOR_REPORT_AMD=1` | Report an AMD GPU to OpenGL games that misbehave on "Apple" GPUs (e.g. Godot 3) |

Logs of games launched from Steam go to `~/Library/Logs/proton-macos/<appid>.log`.

### Known limitations

- **Steam Cloud:** the Mac client does not sync cloud saves of Windows-only games. Download them from
  `https://store.steampowered.com/account/remotestorageapp/?appid=<appid>` and copy them into the game's
  prefix under `~/Library/Application Support/proton-macos/compatdata/<appid>/pfx/drive_c/users/steamuser/`.
- Games installed by `pmac` are not shown as installed in Steam's own page for the game; use
  `pmac shortcut`. Native Steam Play integration (the **Play** button on the original page) is being
  researched ([ADR 0002](docs/adr/0002-steam-play-integration.md)).
- Anti-cheat protected multiplayer games are not expected to work.

## Graphics and Apple software

This project **never distributes** any part of Apple's Game Porting Toolkit (D3DMetal, MetalFX). If you
download GPTK yourself from Apple, put its `redist/lib` in
`~/Library/Application Support/proton-macos/gptk/<version>/` (or set `PROTON_MAC_GPTK`) and use
`PROTON_MAC_GFX=d3dmetal`. Using GPTK is subject to Apple's license terms, which limit it to evaluating
ports. Without it, Proton-macOS uses open-source components (DXVK on MoltenVK, vkd3d, wined3d).

## How it works

Keep the **same contract as Proton on Linux** (the `proton` script, `PROTON_*` variables,
`toolmanifest.vdf`, `compatibilitytools.d`), so that the work is easy to rebase on upstream and could one
day be adopted by Valve as native Steam Play support on macOS.

```
Windows game (.exe, x86/x86_64)
 └─ Wine (Valve's fork, `macos` branch) — x86_64 under Rosetta 2, winemac.drv, new WoW64
     ├─ Graphics: D3DMetal (from the user's own GPTK) | DXVK → MoltenVK | wined3d   (PROTON_MAC_GFX)
     ├─ Sync: msync (XNU ulocks)                                                 (PROTON_NO_MSYNC=1)
     └─ lsteamclient → steamclient.dylib of the running Steam client (loaded in-process, x86_64 slice)
 └─ `proton` script (Python) — run / waitforexitandrun / getcompatpath, as on Linux
pmac (Rust) — library, Windows depots (DepotDownloader, QR login), launching, Steam shortcuts
```

Key research results (details in [docs/research/](docs/research/00-findings.md)):

- `steamclient.dylib` is universal (`x86_64 arm64`), so Wine under Rosetta can load it in-process.
- The macOS Steam client already contains the full Steam Play compatibility manager. It is gated by a single
  `oslist == "linux"` check. With that check flipped at runtime, Steam on macOS registers a
  `windows → macos` tool, downloads Windows depots and launches the tool with the same
  `waitforexitandrun` + `STEAM_COMPAT_*` contract as on Linux.

Every patch carried against Wine and Proton is listed, with the reason, in [docs/patches/](docs/patches).

## Building from source

```sh
git clone --recurse-submodules --shallow-submodules https://github.com/albvalort/proton-macos.git
cd proton-macos
brew install bison flex autoconf automake pkgconf freetype   # arm64 Homebrew, for the native build tools
# llvm-mingw (PE toolchain) into ~/.local/opt/llvm-mingw:
#   https://github.com/mstorsjo/llvm-mingw/releases (ucrt-macos-universal)
scripts/doctor.sh                  # checks the environment
scripts/build-deps.sh              # x86_64 unix dependencies (FreeType from source, MoltenVK, DXVK-macOS)
scripts/build-macos.sh all         # Wine: cross build arm64 → x86_64 into dist/wine
scripts/build-proton-modules.sh    # lsteamclient and steam.exe
scripts/package.sh --install       # dist/proton-macos (+ pmac), symlinked into Steam's compatibilitytools.d
```

Rust (`cargo`) is needed for `pmac`. A full build takes a while; `scripts/build-macos.sh rebuild` only
recompiles what changed.

### Releases

`scripts/release.sh <version>` turns a build into `dist/proton-macos-<version>.tar.xz` (the tool, `pmac`,
`compat/`, licenses and `install.sh`). The [Release workflow](.github/workflows/release.yml) does the whole
build on a GitHub Apple Silicon runner: pushing a tag `vX.Y.Z` publishes a GitHub release; running it
manually only uploads the archive as a workflow artifact.

## Repository layout

| Path | Contents |
|---|---|
| `external/proton`, `external/wine` | Forks of Valve's Proton and Wine (`macos` branch), as submodules |
| `launcher/` | `pmac`, the launcher (Rust) |
| `compat/` | Per-game settings and notes (`<appid>.yaml`) |
| `scripts/` | Environment check, build, packaging, release and install scripts |
| `tests/` | Steam bridge and msync tests |
| `tools/` | Debugging and reverse-engineering helpers |
| `docs/research/` | Findings, with evidence and confidence levels |
| `docs/adr/` | Architecture decision records |
| `docs/patches/` | Every patch we carry against upstream, and why |
| `docs/bench/` | Benchmarks |

## License

Our own code is BSD-3-Clause ([LICENSE](LICENSE)). Wine is LGPL-2.1-or-later; other components keep their
own licenses ([NOTICE](NOTICE)).
