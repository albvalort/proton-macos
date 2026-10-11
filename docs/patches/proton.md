# Parches sobre Proton (rama `macos`)

Base: `ValveSoftware/Proton` en el tag `proton-11.0-2` (`db9e6ff`). Commits en `albvalort/Proton@macos`.

## lsteamclient (hito 5)

| Commit | Fichero | Problema | Arreglo |
|---|---|---|---|
| `40a8b6c` | `unixlib.cpp` | El `steamclient.dylib` de macOS no exporta `Steam_IsKnownInterface` ni `Steam_NotifyMissingInterface`, y `LOAD_FUNC` los exigía (`steamclient_init` fallaba). | Carga opcional con `WARN`. Sin el export, `IsKnownInterface` devuelve `true` y la búsqueda real de la interfaz decide; `NotifyMissingInterface` no hace nada. |
| `40a8b6c` | `unixlib.cpp` | `std::max(...)` choca con la macro `max()` de `minwindef.h`. | `(std::max)(...)` |
| `eaa9084` | `unix_private.h` | `winbase.h` envenena `wcsncpy`/`strncpy` con macros; libc++ en macOS incluye `wchar.h` después y falla. | Incluir `string.h` y `wchar.h` antes de `windef.h`/`winbase.h`. |
| `7963a85` | `unix_steam_input_manual.cpp` | `#error` sin conversión VK→tecla nativa para macOS (la usa `ISteamHTMLSurface::KeyDown/KeyUp`). | Tabla VK → `kVK_*` (HIToolbox/Events.h), que es lo que espera CEF en macOS. |

La rama `__APPLE__` de `steamclient_init`, que carga `$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamclient.dylib`, ya
existía en Proton y funciona sin cambios.

## Build

`scripts/build-proton-modules.sh` replica `make/rules-makedep.mk` de Proton: reutiliza el `Makefile` generado del
build de Wine, apunta `SUBDIRS` a las fuentes del módulo (lsteamclient, steam_helper) y genera las reglas con `makedep`. El lado unix se
enlaza contra `ntdll.so` mediante `LDFLAGS`; Proton lo hace con `UNIX_LIBS`.

## Script `proton` (hito 6)

Commit `8079308`. Todos los cambios van detrás de `IS_DARWIN = sys.platform == "darwin"`.

| Cambio | Motivo |
|---|---|
| `ld_path_var = DYLD_FALLBACK_LIBRARY_PATH` con `files/lib`, conservando `/usr/local/lib:/usr/lib` | Wine hace `dlopen` de sus dependencias unix por nombre; dyld ignora `LD_LIBRARY_PATH` y, si se fija `DYLD_FALLBACK_LIBRARY_PATH`, reemplaza el valor por defecto. |
| `set_dir_casefold_bit` no hace nada | ioctl de ext4. APFS ya es case-insensitive por defecto. |
| Sin `WINEFSYNC` | `futex_waitv` solo existe en Linux; el sustituto es msync (hito 4). |
| `use_nvapi = False` | NVIDIA no aplica. |
| OpenVR/OpenXR opcionales | No se compilan para macOS. |
| `PROTON_MAC_GFX` (por defecto `wined3d`) | Selector de backend gráfico; se amplía en el hito 3. |
| Sin `wine-preloader` en `run()` | No existe en macOS: el loader reserva la memoria con segmentos Mach-O. |
| `ActiveProcess\SteamClientDll[64]` → `C:\windows\system32\lsteamclient.dll` | Steam para Mac no trae `legacycompat/steamclient*.dll`. Copiar `lsteamclient` con ese nombre activa la redirección de 32 bits del loader de Valve (pensada para la DLL real), y `steam_api.dll` se queda en un bucle (diagnosticado con `sample`: el hilo gira dentro de `steam_api.dll`). Apuntar el registro a `lsteamclient` evita la redirección. |
| `toolmanifest_macos.vdf` | Igual que el de Linux, pero sin `require_tool_appid` (no hay Steam Linux Runtime). |

`scripts/package.sh` monta la herramienta en `dist/proton-macos` con la misma estructura que Proton en Linux
(`proton`, `toolmanifest.vdf`, `compatibilitytool.vdf` con `to_oslist macos`, `version`, `files/`). Con
`--install` la enlaza en `compatibilitytools.d` del cliente de Steam y de steamcmd.
