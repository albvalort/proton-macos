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

`scripts/build-lsteamclient.sh` replica `make/rules-makedep.mk` de Proton: reutiliza el `Makefile` generado del
build de Wine, apunta `SUBDIRS` a las fuentes de lsteamclient y genera las reglas con `makedep`. El lado unix se
enlaza contra `ntdll.so` mediante `LDFLAGS`; Proton lo hace con `UNIX_LIBS`.
