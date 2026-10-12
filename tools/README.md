# Herramientas de depuración

- `re/`: ingeniería inversa del cliente de Steam (`xref.py`, `strnicmp_spy.c`).
- `input/winput.c`: clics, teclas y movimiento de ratón por guion dentro de un prefijo de Wine,
  para llegar a una partida sin intervención (`winput.exe <título> click X Y sleep MS key VK …`).
- `glcapture/glcapture.c`: interpone `CGLFlushDrawable` en una app OpenGL **nativa** de macOS y guarda
  fotogramas (`GLCAPTURE_DIR`, `GLCAPTURE_INTERVAL`), para comparar con Wine (`WINE_GL_CAPTURE`).
- `cloud/cloudsync.c`: lista/descarga ficheros de Steam Cloud vía la API. No ve los ficheros
  auto-cloud (Lingo devuelve 0), así que de momento solo sirve para juegos que usan `ISteamRemoteStorage`.

Compilar los `.exe` con `~/.local/opt/llvm-mingw/bin/x86_64-w64-mingw32-clang -O2`.
