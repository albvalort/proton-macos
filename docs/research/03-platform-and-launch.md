# (c) Decisión de plataforma (oslist) y lanzamiento en el cliente de Mac

Solo documentación. No se ha modificado nada. Análisis estático del slice x86_64 de
`steamclient.dylib` (build 1788652215). Las direcciones son relativas a ese build y **cambiarán** con
cada actualización.

Reproducir:

```sh
lipo .../steamclient.dylib -thin x86_64 -output sc_x64.dylib
otool -tV sc_x64.dylib > sc_x64.asm     # ~3 s, 5,6 M líneas; anota "literal pool for: ..."
grep -n 'literal pool for: "config/oslist"' sc_x64.asm
```

## 1. Lectura de oslist

| Dirección | Qué hace | Evidencia |
|---|---|---|
| `0x551340` | Analiza `config/oslist` de una entrada de lanzamiento (`V_isnumeric`, `V_strnicmp`, `V_atoi`). | literal `"config/oslist"` |
| `0x5513de` | `GetAppStateInfo`: compara la plataforma con la cadena `"macos"` (`0x5516d0`). | literales `"GetAppStateInfo"` y `"macos"` |
| `0x553384…` | `IsAppDlcInstalled`: `oslist` y `config/oslist` con `V_stristr`. | literales |
| `0x545d60`, `0x54a22b`, `0x54b334`, `0x551937` | Lecturas de `osarch`. | literal `"osarch"` |

Valores de plataforma presentes: `windows`, `macos`, `linux`, `macos64`, `arm64`.

## 2. Steam Play (CCompatManager) viene compilado en el cliente de Mac ⚠️

Este es el hallazgo más importante para el hito 9. Las rutas de compilación demuestran que
`clientdll/compatmanager.cpp` forma parte del build de Mac:
`/opt/buildbot/buildworker/steam_rel_client_osx/build/src/clientdll/compatmanager.cpp`.

El binario contiene toda la maquinaria de Steam Play de Linux:

- Descubrimiento de herramientas: `/compatibilitytools.d`, `/usr/share/steam/compatibilitytools.d`,
  `/usr/local/share/steam/compatibilitytools.d` (refs en `0x6500bd`–`0x65041d`), `/toolmanifest.vdf`,
  `commandline`, `commandline_waitforexitandrun`, `commandline_getcompatpath`, `require_tool_appid`,
  `%verb%`, `waitforexitandrun`.
- Mapeo app → herramienta: `Software\Valve\Steam\CompatToolMapping`, `CSpecifyAppCompatToolJob`,
  `m_mapAppPlatformOverride`, `m_mapAppInvalidPlatform`, `m_mapCompatEnabled`, campos `src_os`/`dest_os`.
- El entorno que reciben las herramientas: `STEAM_COMPAT_CLIENT_INSTALL_PATH`, `STEAM_COMPAT_DATA_PATH`,
  `STEAM_COMPAT_APP_ID`, `STEAM_COMPAT_TOOL_PATHS`, `STEAM_COMPAT_LIBRARY_PATHS`,
  `STEAM_COMPAT_SHADER_PATH`, `STEAM_COMPAT_INSTALL_PATH`, `STEAM_COMPAT_MOUNTS`, `STEAM_COMPAT_PROTON`.
- Interruptor global: `CCompatManager` guarda un `bool enabled` en `this+0x7b0`. Hay un getter en
  `0x64561c` y una función que imprime `"Disabling compatibility layer."` y lo pone a 0 en
  `0x645628`. A esta última se la llama desde `0x55448a`.

**Hipótesis (confianza media-baja):** el gestor existe en macOS pero no se activa, o no recibe
herramientas válidas para `dest_os=macos`. En esta máquina, `logs/` no tiene ninguna línea de
compat y no existe `~/Library/Application Support/Steam/compatibilitytools.d`.

**Experimento propuesto, barato y reversible**, sin parchear nada (antes del hito 9):

1. Crear `~/Library/Application Support/Steam/compatibilitytools.d/proton-macos-test/` con
   `compatibilitytool.vdf` (`from_oslist "windows"`, `to_oslist "macos"`), `toolmanifest.vdf` y un
   script que solo registre los argumentos y el entorno que recibe.
2. Arrancar Steam con `-compat_log` (la cadena `compat_log` está en el binario) y revisar
   `logs/compat_log.txt`.
3. Ver si la herramienta aparece en Propiedades → Compatibilidad de un juego de Windows.

Si funciona, **el hito 9 no necesita hooks**: Steam lanzaría nuestro `proton` igual que en Linux, con
`STEAM_COMPAT_*` y `SteamAppId`. Eso encaja de lleno con "para que Valve lo pueda adoptar".

### 2.1 Resultado del experimento (2026-10-11)

**El interruptor.** En el constructor de `CCompatManager` (GUI x86_64 `0x642fa5`; steamcmd arm64 `0x6913a4`):

```
m_bEnabled (this+0x7b0) = V_strnicmp(ClientOSList(), "linux", INT_MAX) == 0
```

`ClientOSList()` (`0x54b526`) lee `"oslist"` del KeyValues de configuración del cliente. Ese valor se
puede sobrescribir con el ConVar **`@sSteamCmdForcePlatformType`** (`windows|macos|linux|android`), y la
plataforma de bitness con `@sSteamCmdForcePlatformBitness`.

**El ConVar llega tarde.** `CCompatManager` se construye al cargar la Steam API. Los comandos `+cmd`
(incluido `+set_var`) se ejecutan después. Comprobado con un shim `DYLD_INSERT_LIBRARIES`
(`tools/re/strnicmp_spy.c`) sobre steamcmd: el constructor recibe `"macos"` aunque se pase
`+@sSteamCmdForcePlatformType linux`. En el GUI, `+@sSteamCmdForcePlatformType` da
`command not found`; `set_var` existe.

**Forzado en tiempo de ejecución** (solo steamcmd, sin tocar ficheros; `SPY_FORCE_OFFSET=0x6913b8`):
`compat_log.txt` se crea y el gestor funciona:

```
Processing local tool list at ~/.local/opt/steamcmd/compatibilitytools.d/proton_macos_probe/compatibilitytool.vdf...
Registering tool proton_macos_probe, AppID 0
Ignoring tool proton_macos_probe as it's for a different target platform linux.
```

Conclusiones:

| Conclusión | Confianza |
|---|---|
| Steam Play está compilado y funciona en macOS; lo apaga un único `bool` que exige `oslist == "linux"`. | Alta |
| Las herramientas se buscan en `<raíz del cliente>/compatibilitytools.d` y se filtran por `to_oslist` contra la plataforma **real** (`macos`). Una herramienta `from_oslist windows` / `to_oslist macos` es exactamente el caso que el código contempla. | Alta |
| Sin modificar el comportamiento no se activa: el ConVar se aplica después del constructor. | Alta |
| Integración mínima: invertir ese único chequeo (hook o *interpose* sobre un **cliente re-firmado o steamcmd**). Mucho más pequeño y robusto que hookear el chequeo de oslist y el lanzamiento por separado (plan original del hito 9). Para Valve, adoptarlo sería un cambio de una línea. | Media-alta |
| `STEAM_COMPAT_TOOL_MAPPINGS` (variable de entorno, separada por comas, parseada con `strtoul`/`strtol`) permite mapear app→herramienta sin tocar `config.vdf`. Formato exacto pendiente. | Media |

### 2.2 Prueba de extremo a extremo con steamcmd (2026-10-11) ✅

Montaje: `compatibilitytools.d/proton_macos_probe` con `from_oslist windows` / `to_oslist macos`, que solo
registra los argumentos y el entorno que recibe. Mapeo en `config.vdf` → `CompatToolMapping/585690`
(Minimalism, solo Windows). Chequeo invertido con el shim (`SPY_FORCE_OFFSET=0x6913b8`).

1. **Registro.** `compat_log.txt`: `Registering tool proton_macos_probe` → `Mapping AppID 585690 to tool
   "proton_macos_probe" with priority 250` → `Command prefix ... set to: "'.../proton_macos_probe/.'/probe run "`.
2. **Instalación.** `app_status` deja de mostrar `Invalid Platform`. `app_update 585690` descarga el depot
   de **Windows** (`Minimalism.exe: PE32 executable (GUI) Intel 80386`) y los depots compartidos de
   redistribuibles (228986 y 228990 de la app 228980), igual que Steam Play en Linux.
3. **Lanzamiento.** `app_run 585690` ejecuta
   `'.../proton_macos_probe/.'/probe waitforexitandrun '<install>/Minimalism.exe'` con cwd en el directorio
   del juego y este entorno:

```
STEAM_COMPAT_APP_ID=585690
STEAM_COMPAT_CLIENT_INSTALL_PATH=<directorio que contiene steamclient.dylib>
STEAM_COMPAT_DATA_PATH=~/Library/Application Support/Steam/steamapps/compatdata/585690
STEAM_COMPAT_INSTALL_PATH=<install dir>
STEAM_COMPAT_SHADER_PATH=.../shadercache/585690
STEAM_COMPAT_MOUNTS=.../common/Steamworks Shared
STEAM_COMPAT_PROTON=1
STEAM_COMPAT_LIBRARY_PATHS= / STEAM_COMPAT_TOOL_PATHS=   (vacías)
STEAM_DYLD_INSERT_LIBRARIES=<cliente>/steamloader.dylib
SteamAppId=SteamGameId=SteamOverlayGameId=585690, SteamClientLaunch=1, SteamEnv=1
PROTON_CRASH_REPORT_DIR=/tmp/proton_crashreports
```

**Es el mismo contrato que Proton en Linux.** `STEAM_COMPAT_CLIENT_INSTALL_PATH` es justo lo que lee la
rama `__APPLE__` de `lsteamclient/unixlib.cpp` para cargar `steamclient.dylib`.

### 2.3 El cliente gráfico

- `steam_osx` (el cliente real) **no tiene hardened runtime** (`codesign` muestra `flags=0x0`). Solo lo
  tiene el arrancador `/Applications/Steam.app` (`flags=0x10000(runtime)`).
- El chequeo está en el mismo offset arm64 (`steamclient.dylib+0x6913b8`, `cmp w0,#0` → `strb w8,[x19,#0x7b0]`).
- En principio, por tanto, se puede activar Steam Play en el Steam gráfico **sin modificar ni re-firmar ningún
  fichero**: lanzando `steam_osx` con un shim `DYLD_INSERT_LIBRARIES`. **Sin probar**: el lanzamiento con
  inyección en el cliente gráfico no está autorizado en esta sesión y queda a decisión del usuario.

### 2.4 De extremo a extremo con nuestro Proton (2026-10-11) ✅

`scripts/steamcmd.sh` (HOME aislado) + shim + `CompatToolMapping/585690 → proton_macos`:
`app_update 585690` descarga el depot de Windows y `app_run 585690` ejecuta
`proton_macos/proton waitforexitandrun <...>/Minimalism.exe`. Minimalism (PE32, D3D9 → wined3d → OpenGL)
arranca a pantalla completa.

Hallazgos:

- **Steam lanza la herramienta como proceso x86_64** (Rosetta) cuando el juego es x86. El shim
  `/usr/bin/python3` de las CLT de macOS 27 necesita `libxcrun`, que es solo arm64, y falla. Por eso `package.sh`
  instala el script de Proton como `proton.py` y `proton` es un lanzador
  `arch -arm64 /usr/bin/python3 proton.py` (Wine sigue arrancando como x86_64).
- **steamcmd no ofrece el servidor IPC para juegos** (`[S_API FAIL] ... ipcserver GetSteamPath failed`;
  en Proton, `steamclient_init_registry: Failed to connect to Steam`). Los juegos lanzados por steamcmd
  funcionan, pero sin Steam API (logros, overlay, etc.). La API sí funciona con el cliente gráfico abierto
  (hito 5).
- steamcmd y el cliente gráfico no pueden compartir directorio de datos: cada uno sobrescribe el token de
  sesión del otro (`config.vdf` → `ConnectCache`). `scripts/steamcmd.sh` usa un HOME propio.
- `installscript_posix.cpp: Standalone evaluator returned error code`: los installscripts (redistribuibles)
  se ejecutan a través de la herramienta con `proton run`. Pendiente de revisar.

### Consecuencias para el plan

- **Hito 6.** El script `proton` debe implementar el contrato anterior (`waitforexitandrun`, `run`,
  `getcompatpath`) y poner `compatibilitytool.vdf` con `to_oslist macos`.
- **Hito 7.** Con la herramienta registrada, el propio Steam descarga los depots de Windows (steamcmd aislado).
  DepotDownloader pasa a ser solo un plan B. Para que los juegos tengan Steam API hay que lanzarlos con el
  cliente gráfico abierto: `pmac run` llama directamente a `proton run`, con las variables de Steam, mientras
  el GUI sirve el IPC; o bien, en el hito 9, el propio GUI lanza la herramienta.
- **Hito 9.** Ya no hacen falta hooks del chequeo de oslist ni del lanzamiento, ni una copia re-firmada: basta
  con invertir **un** booleano. Es la demostración de que el soporte nativo de Valve sería un cambio de
  una línea (`oslist == linux` → `oslist in {linux, macos}`).
- **Fragilidad.** El offset depende del build. La versión de producción debe localizar el patrón
  (`"linux"` + `V_strnicmp` + store en `+0x7b0`) y, si no lo encuentra, no hacer nada.

## 3. Lanzamiento del proceso

- Importaciones del slice x86_64: `posix_spawn` y `posix_spawn_file_actions_addchdir_np`,
  `posix_spawnattr_setbinpref_np` (Steam elige el slice x86_64/arm64 al lanzar), además de `fork`,
  `execvp`, `system` y `popen`.
- Resolución de la entrada de lanzamiento: alrededor de `0x54fff1`
  (`"Failed running app %u (entry for launch option %u not found)"`), invocada desde `CAPIJobLaunchApp`.
- Los lanzamientos se registran en `logs/gameprocess_log.txt`.

| Conclusión | Confianza |
|---|---|
| El filtrado por plataforma se basa en `oslist`/`config/oslist` y en `osarch` de appinfo; las funciones están localizadas arriba. | Media (localizado por referencias a cadenas, sin decompilar) |
| CCompatManager (Steam Play) está compilado en el cliente de Mac con descubrimiento de `compatibilitytools.d`. | Alta |
| Ese gestor se puede activar en macOS sin parches. | **Desconocida**: requiere el experimento de la sección 2 |
| Steam lanza los juegos con `posix_spawn` eligiendo la arquitectura. | Media-alta |
