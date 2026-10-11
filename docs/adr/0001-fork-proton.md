# ADR 0001: Hacer fork de Proton y del Wine de Valve

- Estado: aceptada
- Fecha: 2026-10-11

## Contexto

Queremos ejecutar juegos de Windows de Steam en macOS Apple Silicon. Hay tres bases posibles:

1. **Wine upstream** (WineHQ), como hacen Whisky o los builds de Gcenx.
2. **Wine de CodeWeavers** (CrossOver), cuyo código LGPL se publica.
3. **Proton de Valve**: su fork de Wine más lsteamclient, el script `proton`, DXVK/vkd3d y los app fixes.

## Decisión

Hacer fork de `ValveSoftware/Proton` y `ValveSoftware/wine`, con una rama `macos` creada desde el último
tag estable (`proton-11.0-2`; el Wine fijado es `dc26e61`), e incluirlos como submódulos en `external/`.
De upstream y CrossOver traeremos solo los parches necesarios para macOS (winemac.drv, msync…),
documentados en `docs/patches/`.

## Motivos

- **Integración con Steam.** Proton ya resuelve lo difícil: lsteamclient (que traduce la API de Steamworks
  entre Windows y el host), el contrato `compatibilitytools.d` y los app fixes por juego. La investigación
  del hito 0 muestra que el cliente de Steam para Mac trae compilado ese mismo contrato y que lsteamclient
  ya tiene una rama `__APPLE__`.
- **Adopción por Valve.** Un fork de Proton con cambios aislados es lo único que Valve podría integrar
  sin rehacerlo.
- **Compatibilidad.** Los parches de juegos de Proton (fsync/esync, hacks de lanzadores, etc.) se heredan.

## Consecuencias

- Hay que mantener el rebase con Proton. Mitigación: cambios mínimos y aislados (`#ifdef __APPLE__`,
  ficheros nuevos) y un registro de parches.
- El Wine de Valve no se prueba en macOS; winemac.drv puede tener regresiones respecto a upstream
  (hito 2).
- Los submódulos son superficiales (`shallow = true`): para rebases hay que hacer
  `git fetch --unshallow` en el submódulo.
- Los forks son públicos (GitHub no permite forks privados de repos públicos).
