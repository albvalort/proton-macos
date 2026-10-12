# Debugging tools

- `re/`: reverse engineering of the Steam client (`xref.py`, `strnicmp_spy.c`).
- `input/winput.c`: scripted clicks, keys and mouse motion inside a Wine prefix, to reach a game without
  user interaction (`winput.exe <window title> click X Y sleep MS key VK …`).
- `glcapture/glcapture.c`: interposes `CGLFlushDrawable` in a **native** macOS OpenGL app and saves frames
  (`GLCAPTURE_DIR`, `GLCAPTURE_INTERVAL`), to compare with Wine (`WINE_GL_CAPTURE`).
- `cloud/cloudsync.c`: lists/downloads Steam Cloud files through the API. It does not see auto-cloud files
  (Lingo returns 0), so for now it only helps with games that use `ISteamRemoteStorage`.

Build the `.exe` tools with `~/.local/opt/llvm-mingw/bin/x86_64-w64-mingw32-clang -O2`.
