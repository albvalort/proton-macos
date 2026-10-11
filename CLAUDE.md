# Proton-macOS

Port de Proton (Wine + lsteamclient + script `proton`) a macOS Apple Silicon para ejecutar juegos
de Windows de Steam. Nombre provisional; no implica respaldo de Valve.

## Arquitectura

```
Juego .exe (Windows x86_64)
  └─ Wine de Valve (fork, rama macos) — x86_64 bajo Rosetta 2, winemac.drv, WoW64 nuevo
       ├─ Gráficos: D3DMetal (del GPTK del usuario) | DXVK→MoltenVK | wined3d   (PROTON_MAC_GFX)
       ├─ Sync: msync (semáforos Mach)                                           (PROTON_NO_MSYNC=1)
       └─ lsteamclient (lado PE + lado unix) → steamclient.dylib del cliente Steam en ejecución
  └─ script `proton` (Python, fork) — mismo contrato que en Linux
pmac (launcher/, Rust): login QR, biblioteca, depots de Windows, accesos en Steam
steam-hook/ (experimental, opt-in): integración en copia re-firmada de Steam.app
```

## Estructura del repo

- `scripts/` — `doctor.sh`, `build-macos.sh`, `bench.sh`
- `external/proton`, `external/wine` — submódulos (forks, rama `macos`)
- `launcher/` — `pmac` en Rust
- `steam-hook/` — experimental
- `compat/<appid>.yaml` — base de compatibilidad
- `docs/research/` — hallazgos de ingeniería inversa (con evidencia y nivel de confianza)
- `docs/patches/` — un fichero por componente: cada parche, por qué y de dónde viene
- `docs/adr/` — decisiones de arquitectura (`NNNN-titulo.md`)
- `docs/bench/` — resultados de rendimiento
- `docs/STATUS.md` — estado por hito

## Hechos del entorno (verificados)

- macOS 27 en arm64. Wine corre como x86_64 bajo Rosetta 2.
- **`/Applications/Steam.app` es solo el bootstrapper.** El cliente real está en
  `~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/`
  (`steamclient.dylib`, `steam_osx`, etc.). Usar siempre esta ruta.
- `steamclient.dylib` es universal (`x86_64 arm64`): se puede cargar en proceso desde Wine x86_64.
- Toolchains en espacio de usuario: `~/.local/opt/llvm-mingw` (PE), `~/.local/opt/ghidra_*` (análisis).
- Homebrew ya no admite x86_64: las dependencias unix x86_64 de Wine se compilan con `scripts/build-deps.sh`
  en `~/.local/opt/proton-macos-deps/x86_64`. Nunca usar Homebrew de `/opt/homebrew` (arm64) para enlazar Wine.
- **Las Command Line Tools de macOS 27 son solo arm64** (clang, make, ld y también `libxcrun`): nada de
  `arch -x86_64` para compilar. Se hace compilación cruzada desde arm64 (`clang -arch x86_64`,
  `--build=aarch64-apple-darwin --host=x86_64-apple-darwin`). Wine usa sus herramientas nativas arm64 vía
  `--with-wine-tools` (ver `scripts/build-macos.sh`).
- `steam_osx` no tiene hardened runtime; `/Applications/Steam.app` sí. Steam Play está compilado en el
  cliente de Mac y lo desactiva un único chequeo (`docs/research/03-platform-and-launch.md`).
- steamcmd en `~/.local/opt/steamcmd`. **Usarlo siempre con `scripts/steamcmd.sh`**, que le da un HOME propio
  (`~/.local/share/proton-macos/steamcmd-home`). Si comparte `~/Library/Application Support/Steam` con el
  Steam gráfico, cada cliente sobrescribe el token de sesión del otro (`config.vdf` → `ConnectCache`).
  No reiniciar el Steam gráfico para hacer pruebas: usar steamcmd.
- REA (MCP + CLI `npx rea-agents`) para ingeniería inversa de binarios.

## Reglas

1. **Nunca redistribuir nada de Apple** (GPTK, D3DMetal, MetalFX). Solo detectar la instalación del
   usuario y referenciarla. Ni en el repo, ni en paquetes, ni en CI. Ojo: la licencia de GPTK limita
   su uso a evaluación de ports; documentarlo y no hacer D3DMetal obligatorio.
2. **Nunca modificar el Steam.app original ni el Steam.AppBundle instalado.** Solo análisis estático
   y de solo lectura. Cualquier parche va sobre una copia re-firmada (solo hito 9). Usar cuenta
   secundaria de Steam para pruebas.
3. **Cambios sobre Proton/Wine aislados y documentados** en `docs/patches/` para que el rebase con
   upstream sea trivial. Preferir ficheros nuevos y ramas `if darwin` a reescrituras.
4. **Código de terceros**: solo con licencia compatible (LGPL para Wine, BSD-3 nuestro). Anotar
   el origen en el parche y en `NOTICE`. No copiar a ciegas de CrossOver/Gcenx: entender y citar.
5. **Hallazgos de investigación** siempre con evidencia reproducible (comando + salida) y nivel de
   confianza (alta/media/baja).
6. **Mismo contrato que Proton en Linux**: `proton run`, `proton waitforexitandrun`, variables
   `PROTON_*`, `toolmanifest.vdf`, `user_settings.py`.
7. Antes de pasar de hito, cumplir su criterio de "hecho" y actualizar `docs/STATUS.md`.
8. Nada de manejar contraseñas de Steam: login solo por QR.

## Idioma

Docs internas y commits: español. README, LICENSE, comentarios de código y mensajes de cara a
upstream: inglés.

## Comandos

- `scripts/doctor.sh [--ci]` — comprueba el entorno (código ≠0 si falta algo crítico)
- `scripts/build-deps.sh` — dependencias unix x86_64 de Wine (freetype…) en `~/.local/opt/proton-macos-deps/x86_64`
- `scripts/build-macos.sh [prepare|tools|wine|all]` — Wine en `build/`, instalado en `dist/wine`
