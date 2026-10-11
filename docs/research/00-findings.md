# Hito 0: conclusiones

Fecha: 2026-10-11. Máquina: M2, macOS 27.0.1. Steam para Mac 6.1, build 1788652215.
Proton de referencia: `proton-11.0-2`.

## Resumen

| # | Pregunta | Respuesta | Confianza | Detalle |
|---|---|---|---|---|
| a | ¿`steamclient.dylib` tiene slice x86_64? | **Sí.** Es universal (`x86_64 arm64`), igual que `libtier0_s`, `libvstdlib_s` y `libaudio`. El puente puede cargarlo en proceso; **no hace falta proceso auxiliar con IPC**. | Alta | [01](01-steamclient-arch.md) |
| b | ¿Interfaces del dylib frente a lsteamclient? | Están todas las que piden los juegos (`SteamClient006–023`). **Faltan 2 exportaciones** que Proton carga como obligatorias: `Steam_IsKnownInterface` y `Steam_NotifyMissingInterface`. Se resuelve con un parche pequeño. El ABI es igual que en Linux (`pack(4)` vía `__APPLE__`, SysV). Proton **ya tiene** la ruta `#ifdef __APPLE__` para cargar el dylib. | Alta | [02](02-interfaces.md) |
| c | ¿Dónde se decide si un juego es jugable y cómo se lanza? | Se basa en `oslist`/`config/oslist`/`osarch` de appinfo (funciones localizadas). Se lanza con `posix_spawn` y `setbinpref`. **CCompatManager (Steam Play) completo está compilado en el cliente de Mac**, incluido `compatibilitytools.d`. | Media | [03](03-platform-and-launch.md) |

## Impacto en el plan

1. **Hito 5: el diseño se mantiene (en proceso) y además se simplifica.** El cargador de dylib ya existe
   en Proton. El trabajo real es hacer opcionales 2 símbolos y validar el ABI con `static_assert`.
2. **Hito 9: cambio radical, confirmado (ver [03 §2.2](03-platform-and-launch.md)).** Con steamcmd, Steam en
   macOS registra nuestra herramienta, instala el depot de Windows y la lanza con `waitforexitandrun` y
   las `STEAM_COMPAT_*`, invirtiendo solo un booleano en tiempo de ejecución. Texto original de la hipótesis: Si CCompatManager se puede activar en macOS con una herramienta en
   `~/Library/Application Support/Steam/compatibilitytools.d/`, Steam lanzaría nuestro `proton` sin
   hooks ni copia re-firmada. Antes de invertir en `steam-hook/` hay que hacer el experimento de
   [03 §2](03-platform-and-launch.md#2-steam-play-ccompatmanager-viene-compilado-en-el-cliente-de-mac-️):
   es barato, reversible y no toca binarios. Requiere reiniciar Steam.
3. Riesgo nuevo, sin verificar: `steamclient.dylib` enlaza AppKit/Carbon y podría interferir con el
   `NSApplication` de winemac.drv al cargarse dentro del proceso de Wine.

## Validación posterior (hito 5, 2026-10-11)

La conclusión (a)/(b) quedó confirmada de extremo a extremo: un `.exe` de Windows bajo nuestro Wine carga
`lsteamclient.so`, que hace `dlopen` del `steamclient.dylib` x86_64 del cliente en ejecución. Funcionan
`CreateInterface`, pipe/usuario, `BLoggedOn`, `GetAppID`, `GetPersonaName`, `RequestCurrentStats`,
`SetAchievement` y `StoreStats` con sus callbacks. No hizo falta ningún proceso auxiliar con IPC.

## Estado del entorno (`scripts/doctor.sh`)

Comprobaciones críticas en verde. Avisos pendientes que no se pueden automatizar:

- **Dependencias x86_64 de Wine**: Homebrew ya no admite x86_64 en macOS (el instalador se niega a
  ejecutarse bajo Rosetta: "Homebrew on macOS is only supported on Apple Silicon processors!").
  Decisión: compilarlas desde el código fuente con `scripts/build-deps.sh` en
  `~/.local/opt/proton-macos-deps/x86_64`, sin `sudo` y reproducible en CI. Hito 2.
- **GPTK/D3DMetal**: se descarga con Apple ID desde developer.apple.com. Hará falta en el hito 3.

Instalado durante el hito 0, en espacio de usuario: llvm-mingw 20261006 (`~/.local/opt/llvm-mingw`),
OpenJDK 21 (brew), Ghidra 12.1.4 (`~/.local/opt/ghidra_12.1.4_PUBLIC`) y REA 6.4.0 (MCP + skill).
