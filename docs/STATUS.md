# Estado

| Hito | Descripción | Estado |
|---|---|---|
| 0 | Entorno e investigación de bloqueos | ✅ Hecho. `doctor.sh` sin fallos críticos; (a), (b) y (c) respondidas con evidencia ([findings](research/00-findings.md)) |
| 1 | Esqueleto del repo, forks y CI | ✅ Hecho. Forks `albvalort/Proton` y `albvalort/wine` (rama `macos`), clon con submódulos verificado, CI en verde |
| 2 | Wine de Valve compilando en macOS | ✅ Compila (cruzado arm64→x86_64) con 9 parches ([patches/wine.md](patches/wine.md)). `wine cmd` funciona; `notepad` y `winecfg` abren ventanas nativas (pendiente tu validación visual) |
| 3 | Gráficos: D3DMetal con fallback a DXVK | ⏳ Requiere que el usuario instale GPTK |
| 4 | msync | ⏳ |
| 5 | Puente lsteamclient → steamclient.dylib | ✅ Hecho. `tests/steam-bridge/steamtest.exe` (Wine en macOS) conecta con el Steam en marcha, lee usuario y AppID y desbloquea `ACH_WIN_ONE_GAME` de Spacewar; el perfil público muestra "1 of 5". Parches en [patches/proton.md](patches/proton.md) |
| 6 | Script `proton` para macOS | ✅ Hecho. `proton run`/`waitforexitandrun` funcionan como en Linux. Steam (steamcmd con Steam Play activado) instala Minimalism (depot de Windows) y lo lanza a través de `proton_macos`; el juego (PE32, D3D9→wined3d→OpenGL) corre a pantalla completa. `steamtest.exe` pasa por `proton run` y habla con Steam |
| 7 | Launcher y descarga de depots | ⏳ Steam ya descarga depots de Windows con Steam Play activo |
| 8 | Rendimiento | ⏳ |
| 9 | Integración en el cliente de Steam | 🔬 Validada con steamcmd ([ADR 0002](adr/0002-steam-play-integration.md)) |
| 10 | Publicar | ⏳ |

## Entorno de pruebas

- M2, macOS 27.0.1, Steam para Mac 6.1 (build 1788652215), steamcmd 1788292693.
- Juego de prueba solo de Windows: Minimalism (585690), 9 MB, PE32. Candidato DX11 con logros: ANIMAL WELL (813230).
