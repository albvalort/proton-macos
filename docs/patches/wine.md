# Parches sobre el Wine de Valve (rama `macos`)

Base: `ValveSoftware/wine` en `dc26e61` (el Wine fijado por `proton-11.0-2`, Wine 11.0).
Commits en `albvalort/wine@macos`: `20085ed`..`bac71f0` (un commit por arreglo, mensajes listos para upstream).
Todos los parches son LGPL-2.1-or-later, como Wine. Criterio: cambios mínimos y aislados con
`#ifdef`, para que el rebase con Proton sea trivial.

## Build en macOS (hito 2)

Wine upstream 11.0 compila en macOS. Los fallos vienen de código que Valve añadió y que asume Linux.

| # | Fichero | Problema | Arreglo | Origen |
|---|---|---|---|---|
| 1 | `dlls/ntdll/unix/loader.c` | `#include <malloc.h>` y `mallopt(M_PERTURB)` (glibc) | `#ifdef __linux__` / `#ifdef M_PERTURB` | propio |
| 2 | `dlls/ntdll/unix/signal_x86_64.c` | `set_thread_teb()` usa `arch_prctl(ARCH_SET_GS)` | En macOS, no-op. En código unix, `%gs` contiene el TSD de pthread y Wine lo cambia al TEB en las transiciones de syscall con `_thread_set_tsd_base`, como hace upstream (que no tiene `set_thread_teb`). | propio, siguiendo el diseño de upstream |
| 3 | `dlls/ntdll/unix/sync.c`, `server/inproc_sync.c` | `ntsync_tmp.h` incluye `<linux/types.h>` | Incluir solo en `__linux__`. El código ya cae al camino sin ntsync cuando `NTSYNC_IOC_*` no está definido. | propio |
| 4 | `server/fsync.c`, `dlls/ntdll/unix/fsync.c` | `syscall(__NR_futex…)` / `__NR_futex_waitv` (449) | Fuera de Linux, los helpers devuelven `ENOSYS`. **Importante:** el `#define __NR_futex_waitv 449` habría invocado la syscall 449 *de Darwin*. fsync ya se desactiva en tiempo de ejecución fuera de Linux (`fsync_check_support`). | propio |
| 5 | `dlls/win32u/opengl.c` | El fshack (`framebuffer_surface_*`) se define dentro de `#ifdef SONAME_LIBEGL`, pero Valve lo usa fuera | Stubs en la rama sin EGL: nunca se necesita ni se crea, y `funcs` nunca coincide | propio |
| 6 | `dlls/amd_ags_x64/unixlib.c` | `xf86drm.h`/`amdgpu.h` (libdrm, Linux) | Implementación solo con `HAVE_XF86DRM_H && HAVE_AMDGPU_DRM_H`; si no, `STATUS_NOT_SUPPORTED` | propio |
| 8 | `dlls/ntdll/unix/signal_x86_64.c` (`dump_syscall_fault_return`) | `jmp %rcx` sin `*`: GNU as lo acepta con aviso, pero el ensamblador integrado de clang lo rechaza | `jmp *%rcx` (misma semántica; candidato a upstream de Proton) | propio |
| 9 | `dlls/ntdll/unix/system.c` | `fill_cpu_override` (hack de Valve) usa `sysfs_parse_bitmap`/`fill_performance_core_info`, definidas solo en Linux | Stubs fuera de Linux: el override de CPU sigue funcionando, pero sin preferencia por los núcleos de rendimiento | propio |
| 7 | `dlls/winegstreamer/media-converter/media-converter.h` | `pthread_mutex_t` sin `#include <pthread.h>` (glibc lo arrastra indirectamente) | Añadir el include | propio |

## Opciones de configure (no son parches)

- `--disable-loader64`: `loader64/` es un añadido de Valve que copia `wine64` en `i386-unix` para la
  disposición de Linux. En macOS no hace falta, y su preloader no enlaza `preloader_mac.o`.
- Las herramientas nativas (arm64) se compilan con FreeType de Homebrew: `sfnt2fon` lo necesita para
  generar las fuentes `.fon`.

## Pendiente de revisar

- `err:virtual:try_map_free_area mmap() error Cannot allocate memory` cerca de `0x7fffffff0000` en cada
  arranque (Rosetta). Parece inofensivo (Wine reintenta en otra zona); hay que confirmarlo.

- `winemac.drv`: compararlo con upstream 11.0 en cuanto arranque `winecfg`.
- fsync no existe en macOS. Su sustituto es msync (hito 4).
