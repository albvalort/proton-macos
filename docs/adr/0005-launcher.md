# ADR 0005: The `pmac` launcher and Windows depot downloads

- Status: accepted
- Date: 2026-10-12

## Context

Milestone 7 asks for a launcher (`launcher/`, Rust) to list the library, install the Windows version of a
game, run it with our Proton and add it to the Steam library, with QR login and without handling
passwords. We had to choose between DepotDownloader and steamcmd.

| | steamcmd | DepotDownloader (SteamRE, GPL-2.0) |
|---|---|---|
| Login | User + password + Steam Guard in its own prompt; **no QR** | **QR with the Steam mobile app** (`-qr`), saved token (`-remember-password`) |
| Windows depots | `+@sSteamCmdForcePlatformType windows +app_update` | `-os windows -osarch 64` |
| Coexistence with the Steam GUI | Shares `~/Library/Application Support/Steam`: each invalidates the other's token (needs an isolated HOME, `scripts/steamcmd.sh`) | Own configuration, no interference |
| Distribution | Valve binary, self-updating | Signed release for macOS arm64 (3.4.0) |
| State in Steam | Writes `appmanifest` (Steam sees it installed) | Files only (pmac manages installs) |

## Decision

- **Installation and login: DepotDownloader.** It meets the requirements (QR, no passwords) and does not
  interfere with the Steam GUI. steamcmd stays for the Steam Play experiments (milestone 9).
- **Library without login:** `pmac list` reads the Steam client's caches. `appcache/librarycache/<appid>/`
  gives the games in the library and `appcache/appinfo.vdf` (v29 format, binary KeyValues with a string
  table) gives name, type, `oslist`, `installdir` and launch entries. It is instant (about 0.2 s for 750 apps)
  and needs no network.
- **Running:** `pmac run` reproduces the contract Steam gives a compatibility tool (`STEAM_COMPAT_*`,
  `SteamAppId`/`SteamGameId`, `waitforexitandrun`, see research/03 §2.2), with prefixes in
  `~/Library/Application Support/proton-macos/compatdata/<appid>`. With the Steam GUI running, the game talks
  to it through lsteamclient (achievements, "playing…" presence).
- **Shortcuts:** `pmac shortcut` adds an entry to `userdata/<account>/config/shortcuts.vdf` (binary KeyValues)
  that runs `pmac run <appid>`, with the official artwork Steam already has in `librarycache` (no SteamGridDB
  key). Only with Steam closed, because Steam rewrites the file on exit.
- **Compatibility database:** `compat/<appid>.yaml` with `status`, `backend` (`PROTON_MAC_GFX`), `env` and
  `notes`; `pmac run` applies them (variables in the user's environment take precedence).

## Consequences

- Games installed by pmac do not show as installed in Steam, only as shortcuts. Full integration (Steam
  installs and launches) is milestone 9 (ADR 0002).
- `appinfo.vdf` is an internal Valve format. If it changes, `pmac list` fails with a clear error (the magic
  version is checked).
- DepotDownloader is GPL-2.0: it is used as an external program, not linked.
- Steam Cloud files of Windows-only games are not synced by the Mac client; they have to be copied into the
  prefix by hand for now.
