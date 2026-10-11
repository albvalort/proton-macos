# ADR 0005: Launcher `pmac` y descarga de depots de Windows

- Estado: aceptada
- Fecha: 2026-10-12

## Contexto

El hito 7 pide un launcher (`launcher/`, Rust) para listar la biblioteca, instalar la versión de Windows de un
juego, ejecutarlo con nuestro Proton y añadirlo a la biblioteca de Steam, con login por QR y sin manejar
contraseñas. Había que elegir entre DepotDownloader y steamcmd.

| | steamcmd | DepotDownloader (SteamRE, GPL-2.0) |
|---|---|---|
| Login | Usuario + contraseña + Steam Guard en su propio prompt; **sin QR** | **QR con la app móvil de Steam** (`-qr`), token guardado (`-remember-password`) |
| Depots de Windows | `+@sSteamCmdForcePlatformType windows +app_update` | `-os windows -osarch 64` |
| Convivencia con el Steam gráfico | Comparte `~/Library/Application Support/Steam`: cada uno invalida el token del otro (hace falta un HOME aislado, `scripts/steamcmd.sh`) | Configuración propia, no interfiere |
| Distribución | Binario de Valve, autoactualizable | Release firmada para macOS arm64 (3.4.0) |
| Estado en Steam | Escribe `appmanifest` (Steam lo ve instalado) | Solo ficheros (lo instalado lo gestiona pmac) |

## Decisión

- **Instalación y login: DepotDownloader.** Cumple los requisitos (QR, sin contraseñas) y no interfiere con el
  Steam gráfico. steamcmd queda para los experimentos de Steam Play (hito 9).
- **Biblioteca sin login:** `pmac list` lee las cachés del cliente de Steam. `appcache/librarycache/<appid>/` da
  los juegos de la biblioteca y `appcache/appinfo.vdf` (formato v29, KeyValues binario con tabla de cadenas)
  da nombre, tipo, `oslist`, `installdir` y las entradas de lanzamiento. Es instantáneo (unos 0,2 s para 750
  apps) y no requiere red.
- **Ejecución:** `pmac run` reproduce el contrato que Steam da a una herramienta de compatibilidad
  (`STEAM_COMPAT_*`, `SteamAppId`/`SteamGameId`, `waitforexitandrun`, ver research/03 §2.2), con prefijos en
  `~/Library/Application Support/proton-macos/compatdata/<appid>`. Con el Steam gráfico abierto, el juego
  habla con él a través de lsteamclient (logros, presencia "jugando a…").
- **Accesos directos:** `pmac shortcut` añade una entrada a `userdata/<cuenta>/config/shortcuts.vdf` (KeyValues
  binario) que ejecuta `pmac run <appid>`, con las carátulas oficiales que Steam ya tiene en
  `librarycache` (sin clave de SteamGridDB). Solo con Steam cerrado, porque Steam reescribe el fichero al salir.
- **Base de compatibilidad:** `compat/<appid>.yaml` con `status`, `backend` (`PROTON_MAC_GFX`), `env` y
  `notes`; `pmac run` los aplica (las variables del entorno del usuario tienen prioridad).

## Consecuencias

- Los juegos instalados por pmac no aparecen como instalados en Steam, solo como accesos directos. La
  integración completa (Steam instala y lanza) es el hito 9 (ADR 0002).
- `appinfo.vdf` es un formato interno de Valve. Si cambia, `pmac list` falla con un error claro (se
  comprueba la versión mágica).
- DepotDownloader es GPL-2.0: se usa como programa externo, no se enlaza.
