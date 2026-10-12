# ADR 0002: Steam integration through Steam Play (compatibilitytools.d)

- Status: proposed (validated with steamcmd; not working in the Steam GUI yet)
- Date: 2026-10-11

## Context

The original plan for milestone 9 was to hook two things in a re-signed copy of Steam.app: the platform
check (`oslist`) and the game launch. The milestone 0 research
([03-platform-and-launch.md](../research/03-platform-and-launch.md)) showed that:

- `CCompatManager` (Steam Play) is compiled into the Mac client and is only disabled by
  `m_bEnabled = (oslist == "linux")`.
- With that boolean flipped at runtime, Steam registers a `from_oslist windows / to_oslist macos` tool,
  installs the Windows depot and launches it with `waitforexitandrun <exe>` and all the `STEAM_COMPAT_*`
  variables.
- `steam_osx` has no hardened runtime, so `DYLD_INSERT_LIBRARIES` works without re-signing.

## Decision

- The product is a **standard compatibility tool** in `compatibilitytools.d`, with the same contract as on
  Linux. It works the same however it is installed.
- Client integration (milestone 9) is limited to **flipping that single check** with an injected shim,
  without modifying files. It detects the pattern by signature and disables itself if it is not found.
- Until milestone 9 is stable, the supported path is the launcher (`pmac`, milestone 7), plus shortcuts in
  the library.

## Status of the GUI client (2026-10-12)

- `DYLD_INSERT_LIBRARIES` must not go through SIP-protected binaries (`/usr/bin/nohup`), which strip it.
- The GUI client is arm64 and gets `V_strnicmp` from a library loaded later with `dlopen`, so dyld
  interposing (which worked with steamcmd) fails: `symbol not found in flat namespace '_V_strnicmp'`.
  Another hooking technique is needed; not done.

## Consequences

- Milestone 7 can use Steam itself to download Windows depots; DepotDownloader is plan B.
- For Valve to adopt it, changing one comparison would be enough, which makes the proposal credible.
- Risk: depending on a client internal. Mitigation: signature detection and safe shutdown.
- Legal/account risk: changing the client's behaviour at runtime. Always opt-in, with a warning, and
  tested with secondary accounts.
