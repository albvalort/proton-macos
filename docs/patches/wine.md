# Patches on top of Valve's Wine (`macos` branch)

Base: `ValveSoftware/wine` at `dc26e61` (the Wine pinned by `proton-11.0-2`, Wine 11.0).
Commits in `albvalort/wine@macos`, one commit per fix, with upstream-ready messages.
Every patch is LGPL-2.1-or-later, like Wine. Guideline: minimal, isolated changes behind `#ifdef`, so that
rebasing on Proton stays trivial.

## Building on macOS (milestone 2)

Upstream Wine 11.0 builds on macOS. The failures come from code Valve added that assumes Linux.

| # | File | Problem | Fix | Origin |
|---|---|---|---|---|
| 1 | `dlls/ntdll/unix/loader.c` | `#include <malloc.h>` and `mallopt(M_PERTURB)` (glibc) | `#ifdef __linux__` / `#ifdef M_PERTURB` | own |
| 2 | `dlls/ntdll/unix/signal_x86_64.c` | `set_thread_teb()` uses `arch_prctl(ARCH_SET_GS)` | No-op on macOS. In unix code `%gs` holds the pthread TSD and Wine switches it to the TEB on syscall transitions with `_thread_set_tsd_base`, as upstream does (which has no `set_thread_teb`). Later replaced by CrossOver's TEB model (see D3DMetal). | own, following upstream's design |
| 3 | `dlls/ntdll/unix/sync.c`, `server/inproc_sync.c` | `ntsync_tmp.h` includes `<linux/types.h>` | Only include it on `__linux__`. The code already falls back to the no-ntsync path when `NTSYNC_IOC_*` is not defined. | own |
| 4 | `server/fsync.c`, `dlls/ntdll/unix/fsync.c` | `syscall(__NR_futex…)` / `__NR_futex_waitv` (449) | Outside Linux the helpers return `ENOSYS`. **Important:** `#define __NR_futex_waitv 449` would have invoked *Darwin's* syscall 449. Superseded on macOS by msync (below). | own |
| 5 | `dlls/win32u/opengl.c` | The fshack (`framebuffer_surface_*`) is defined inside `#ifdef SONAME_LIBEGL`, but Valve uses it outside | Stubs in the no-EGL branch: it is never needed or created, and `funcs` never matches | own |
| 6 | `dlls/amd_ags_x64/unixlib.c` | `xf86drm.h`/`amdgpu.h` (libdrm, Linux) | Implementation only with `HAVE_XF86DRM_H && HAVE_AMDGPU_DRM_H`; otherwise `STATUS_NOT_SUPPORTED` | own |
| 7 | `dlls/winegstreamer/media-converter/media-converter.h` | `pthread_mutex_t` without `#include <pthread.h>` (glibc pulls it in indirectly) | Add the include | own |
| 8 | `dlls/ntdll/unix/signal_x86_64.c` (`dump_syscall_fault_return`) | `jmp %rcx` without `*`: GNU as accepts it with a warning, clang's integrated assembler rejects it | `jmp *%rcx` (same semantics; upstream candidate for Proton) | own |
| 9 | `dlls/ntdll/unix/system.c` | `fill_cpu_override` (Valve hack) uses `sysfs_parse_bitmap`/`fill_performance_core_info`, defined on Linux only | Stubs outside Linux: the CPU override still works, without the performance-core preference | own |
| 10 | `server/token.c` | The user SID is derived from `/etc/machine-id`, which does not exist on macOS | `gethostuuid()` (commit `040be76`) | own |

## Configure options (not patches)

- `--disable-loader64`: `loader64/` is a Valve addition that copies `wine64` into `i386-unix` for the Linux
  layout. It is not needed on macOS, and its preloader does not link `preloader_mac.o`.
- The native (arm64) tools are built with Homebrew's FreeType: `sfnt2fon` needs it to generate the `.fon` fonts.

## msync (milestone 4)

Commit `453726a`: fsync on top of XNU ulocks. Design and trade-offs in [ADR 0003](../adr/0003-msync.md).

## D3DMetal (milestone 3)

Ported from the LGPL code of **CrossOver 26.0** (Wine 11.0, © CodeWeavers), with a three-way merge (upstream
11.0 as base, Valve and CrossOver as branches). Commits `e6dd133`, `0c7cc18` and `d04f1c7`.

| Piece | Why D3DMetal needs it |
|---|---|
| CrossOver's TEB model on macOS x86_64 (`signal_x86_64.c`, `thread.c`, `loader.c`) | Upstream/Valve switch the `%gs` base when going between PE and unix. The unix code in `libd3dshared` calls `pthread_self()` on Wine threads and hung in `pthread_setname_np` with `%gs` pointing at the TEB. CrossOver keeps `%gs` on the pthread TSD and mirrors `Self`, the TLS pointer and the `Peb` there. Since macOS uses slot `0x60` for `localtime()`, that slot is redirected to a TLS buffer. |
| ms_abi wrappers (`GPT_ABI_WRAPPER`) on `NtCreateThreadEx`, `NtClose` and the event and semaphore functions | `libd3dshared` calls those `ntdll` functions with the Windows calling convention. Without the wrappers, the arguments arrived wrong and a thread waited forever for a server reply. |
| `libd3dshared` preload and the `pe_module_loaded` notification | Address range used to choose the ABI, and notification of native PE modules. |
| `winemac.drv`: `d3dmetal.c`, `d3dmetal_objc.m` (`macdrv_functions` table, Metal views, registry callbacks) | D3DMetal looks up `macdrv_functions` with `dlsym`; without it, it fails with `Assertion failed: (drv)`. |
| `win32u`: `client_surface_attach()` (own) | In CrossOver, `client_surface_create` registers the surface with the window; upstream does not. Without it, the Metal view kept its initial size (image in the corner over a blue background). |
| `wow64cpu`: 32↔64 transitions with `lretq` under Rosetta 2 (CrossOver, CW HACK 20760), commit `8152fab` | With CrossOver's TEB model, without this, exceptions in 32-bit code were dispatched with the 64-bit stack and WoW64 games (Downwell, Minimalism) quit ("Exception frame is not in stack limits"). |
| `ntdll`: `WINEDLLPATH_PREPEND` (own) | Wine searches its own directory first and `WINEDLLPATH` afterwards. This way GPTK's modules are used from a directory of symlinks in the prefix, without touching the installation. |

## Games (2026-10-12)

| Patch | Why |
|---|---|
| `ntdll`: truncate `BOOLEAN` syscall arguments (`SYSCALL_BOOLEAN_ARG`, own), commit `77017fd` | The Windows x64 ABI leaves the upper bits of narrow arguments undefined and PE code passes `BOOLEAN` with a `movb`; Apple clang assumes they are extended and tests the 32-bit register. The garbage turned `FALSE` into `TRUE`: `GetLogicalDrives()` looped forever because `NtQueryDirectoryObject` always saw `restart=TRUE` (Lingo, Godot 3). Applied to the 42 `ntdll` syscalls with `BOOLEAN` parameters. |
| `winemac.drv`: relative motion for raw input (own), commit `fb90947` | With the cursor inside the window, winemac sent absolute pixel positions and the server forwarded them unchanged as absolute `WM_INPUT`. First-person cameras (Godot 3) expect relative motion, as a real mouse provides on Windows, and did not move. The absolute position now only goes to regular mouse messages and raw input gets macOS's `deltaX/deltaY`, as winex11 does with XInput2. |
| `winemac.drv`: relative mouse mode for hidden, clipped cursors (own), commits `d80520e`, `ff4b41a` | Godot 3 recenters the cursor after every `WM_INPUT`. Warping the macOS cursor that often makes the next events carry the warp back as motion and drops others: the camera stuttered and snapped back. While the cursor is hidden, clipped and the app is active, winemac detaches the cursor from the mouse (`CGAssociateMouseAndMouseCursorPosition`), makes `SetCursorPos` a no-op for the host cursor and reports only relative motion, as native macOS games do. |
| `opengl32`: `WINE_GL_VENDOR_REPORT_AMD` also replaces "Apple" (own, extends Proton's hack), commit `95dc1b3` | Godot 3 disables its depth prepass when `GL_VENDOR` contains "Apple" (`rendering/quality/depth_prepass/disable_for_vendors`), and materials with the "opaque pre-pass" depth draw mode become invisible. Also reproduced with native Godot 3.5.2 on macOS, without Wine. Opt-in per game (`compat/1814170.yaml`). |
| `opengl32`: `WINE_GL_CAPTURE=<dir>` (own, debugging), commit `95dc1b3` | Saves the back buffer as a PPM every `WINE_GL_CAPTURE_INTERVAL` frames before `SwapBuffers`, to see what a game draws without screen recording permission. |

## To review

- `err:virtual:try_map_free_area mmap() error Cannot allocate memory` near `0x7fffffff0000` on every start
  (Rosetta). It looks harmless (Wine retries elsewhere); to be confirmed.
- Proton's `fs_hack_setup_gamma_shader` fails to compile in legacy (2.1) OpenGL contexts on macOS. The
  fullscreen hack is not used on macOS (no EGL), so the gamma shader is useless there.
- `winemac.drv`: compare with upstream 11.0.
