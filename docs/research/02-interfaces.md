# (b) Interfaces de Steamworks: steamclient.dylib frente a lsteamclient

Referencia de Proton: tag `proton-11.0-2` (`lsteamclient/`, SDK más reciente `steamworks_sdk_165`).

## Símbolos que carga lsteamclient

`lsteamclient/unixlib.cpp`, `steamclient_init()`. **Ya tiene una rama `#ifdef __APPLE__`** que carga
`$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamclient.dylib` (con `DYLD_*` como alternativa). Después resuelve
con `LOAD_FUNC` (todos obligatorios: si alguno falla, la inicialización devuelve -1):

| Símbolo | x86_64 | arm64 |
|---|---|---|
| `CreateInterface` | ✅ | ✅ |
| `Steam_BGetCallback` | ✅ | ✅ |
| `Steam_GetAPICallResult` | ✅ | ✅ |
| `Steam_FreeLastCallback` | ✅ | ✅ |
| `Steam_ReleaseThreadLocalMemory` | ✅ | ✅ |
| `Steam_IsKnownInterface` | ❌ **no se exporta** | ❌ |
| `Steam_NotifyMissingInterface` | ❌ **no se exporta** | ❌ |

```
$ nm -arch x86_64 -gU steamclient.dylib | wc -l      # 38 exportaciones en total
$ nm -arch x86_64 -gU steamclient.dylib | grep -E "IsKnownInterface|NotifyMissingInterface"
(vacío)
$ strings -a -arch x86_64 steamclient.dylib | grep NotifyMissingInterface
NotifyMissingInterface   # solo existe como nombre interno o de IPC, no como exportación
```

**Consecuencia:** sin cambios, lsteamclient en macOS falla en `steamclient_init` con
`unable to load Steam_IsKnownInterface`. Arreglo previsto para el hito 5: hacer opcionales esos dos
símbolos. Si falta `IsKnownInterface`, devolver `true` y dejar que `CreateInterface` decida. Si falta
`NotifyMissingInterface`, no hacer nada. Es un parche pequeño y aislado.

## Versiones de interfaz

Se han extraído las cadenas de versión del dylib (`strings`) y se han comparado con los ficheros
`cppISteam*_<VERSION>.cpp` de Proton (212 versiones).

- **SteamClient:** el dylib contiene `SteamClient006` a `SteamClient023`. Proton envuelve 006–021 y 023
  (la 022 no se publicó en el SDK). Cubre todo lo que pedirá un juego.
- **En Proton pero no en el dylib:** solo `SteamNetworkingFakeUDPPort001`. Esta interfaz no se pide
  por nombre a `CreateInterface`; la devuelve `ISteamNetworkingSockets::CreateFakeUDPPort`. No es un
  problema. Otras versiones que parecían faltar (`SteamBilling002`, `STEAMCONTROLLER_INTERFACE_VERSION`,
  `SteamNetworkingSocketsSerialized00x`…) sí están: se ha comprobado con búsqueda exacta.
- **En el dylib pero no en Proton:** versiones internas o antiguas (`SteamClient022`,
  `SteamUtils001/003`, `STEAMVIDEO_INTERFACE_V003–006`, `STEAMTIMELINE_INTERFACE_V002/3`…). Son
  irrelevantes: lsteamclient solo traduce lo que piden los juegos.

## ABI: ¿macOS x86_64 se comporta como Linux x86_64?

- `steamworks_sdk_165/steamclientpublic.h`: `#if defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__)`
  define `VALVE_CALLBACK_PACK_SMALL`, es decir `#pragma pack(4)`. Windows usa `PACK_LARGE` (8).
  **macOS usa el mismo empaquetado que Linux.**
- macOS x86_64 y Linux x86_64 usan la misma convención SysV AMD64 y el mismo modelo LP64, así que el
  layout de structs, `bool`, `wchar_t` (4 bytes) y el paso de argumentos coinciden.
- `gen_wrapper.py` genera el ABI `u64` analizando los headers con libclang en el host Linux
  (`-I/usr/include/x86_64-linux-gnu/`). El código generado puede reutilizarse tal cual. Bastaría con
  regenerarlo en macOS si aparecieran diferencias, y no se espera ninguna.
- macOS no tiene procesos de 32 bits. Los juegos de 32 bits pasan por WoW64 (structs `wow64_*`
  hacia el lado unix de 64 bits), que Proton ya implementa.

| Conclusión | Confianza |
|---|---|
| Las interfaces que necesitan los juegos están disponibles en el dylib. | Alta |
| Faltan las exportaciones `Steam_IsKnownInterface` y `Steam_NotifyMissingInterface`; requiere parche en lsteamclient. | Alta |
| El ABI u64 de macOS es idéntico al de Linux: los thunks generados sirven sin casos nuevos. | Alta (teórica); verificar con `static_assert` de `sizeof`/`offsetof` en el hito 5 |
| La convención de llamada de los métodos virtuales (Itanium C++ ABI) es la misma en clang/macOS y en gcc/Linux. | Alta |
