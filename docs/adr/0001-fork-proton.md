# ADR 0001: Fork Proton and Valve's Wine

- Status: accepted
- Date: 2026-10-11

## Context

We want to run Windows games from Steam on Apple Silicon macOS. There are three possible bases:

1. **Upstream Wine** (WineHQ), as Whisky and Gcenx's builds do.
2. **CodeWeavers' Wine** (CrossOver), whose LGPL code is published.
3. **Valve's Proton**: its Wine fork plus lsteamclient, the `proton` script, DXVK/vkd3d and the app fixes.

## Decision

Fork `ValveSoftware/Proton` and `ValveSoftware/wine`, with a `macos` branch created from the latest
stable tag (`proton-11.0-2`; the pinned Wine is `dc26e61`), and include them as submodules in `external/`.
From upstream and CrossOver we only bring the patches needed for macOS (winemac.drv, msync…),
documented in `docs/patches/`.

## Rationale

- **Steam integration.** Proton already solves the hard parts: lsteamclient (which translates the
  Steamworks API between Windows and the host), the `compatibilitytools.d` contract and per-game app
  fixes. The milestone 0 research shows that the Mac Steam client ships that same contract and that
  lsteamclient already has an `__APPLE__` branch.
- **Adoption by Valve.** A Proton fork with isolated changes is the only thing Valve could merge without
  redoing it.
- **Compatibility.** Proton's game fixes (fsync/esync, launcher hacks, etc.) are inherited.

## Consequences

- Rebasing on Proton must be maintained. Mitigation: minimal, isolated changes (`#ifdef __APPLE__`,
  new files) and a patch log.
- Valve's Wine is not tested on macOS; winemac.drv may have regressions compared to upstream
  (milestone 2).
- The submodules are shallow (`shallow = true`): rebasing needs `git fetch --unshallow` in the
  submodule.
- The forks are public (GitHub does not allow private forks of public repositories).
