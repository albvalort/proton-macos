# (a) Arquitectura de steamclient.dylib

Cliente analizado: Steam para Mac, `CFBundleVersion` 6.1, build **1788652215**, macOS 27.0.1 (M2).
Fecha: 2026-10-11.

## Ubicación

`/Applications/Steam.app` solo arranca Steam. Las bibliotecas del cliente están en:

```
~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/
```

Steam exporta esta ruta en `STEAM_COMPAT_CLIENT_INSTALL_PATH` a las herramientas de compatibilidad
(ver [03](03-platform-and-launch.md)). Proton ya construye `"$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamclient.dylib"`
en macOS.

## Evidencia

```
$ lipo -detailed_info steamclient.dylib
architecture x86_64   size 26706832
architecture arm64    size 25493408

$ lipo -archs libtier0_s.dylib libvstdlib_s.dylib steam_osx
x86_64 arm64   (las tres)

$ otool -arch x86_64 -l steamclient.dylib | grep -A3 LC_BUILD_VERSION
minos 11.0   sdk 26.2

$ codesign -dvv steamclient.dylib
Authority=Developer ID Application: Valve Corporation (MXGJJ98X76)
flags=0x0(none)
```

Dependencias del slice x86_64 (`otool -arch x86_64 -L`): `@loader_path/` para `libtier0_s`,
`libvstdlib_s` y `libaudio`, y además frameworks del sistema (AppKit, Carbon, Foundation, IOKit,
OpenGL, OpenAL, CoreAudio, Security, IOBluetooth…). Todos los frameworks del sistema son universales.

## Conclusiones

| Conclusión | Confianza |
|---|---|
| `steamclient.dylib` y sus dependencias propias (`libtier0_s`, `libvstdlib_s`, `libaudio`) tienen slice x86_64. Wine x86_64 bajo Rosetta puede cargarlas con `dlopen`. | Alta |
| No hace falta un proceso auxiliar arm64 con IPC para el hito 5. | Alta (pendiente de confirmar con un `dlopen` real) |
| Wine no usa hardened runtime, así que la validación de bibliotecas no impide cargar un dylib firmado por Valve. | Media: confirmar en el hito 5 |
| El dylib enlaza AppKit/Carbon. Al cargarse dentro de Wine (que usa AppKit vía winemac.drv) podría competir por el hilo principal o por `NSApplication`. | Media (riesgo, sin verificar) |
