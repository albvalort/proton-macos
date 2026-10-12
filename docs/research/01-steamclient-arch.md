# (a) Architecture of steamclient.dylib

Client analysed: Steam for Mac, `CFBundleVersion` 6.1, build **1788652215**, macOS 27.0.1 (M2).
Date: 2026-10-11.

## Location

`/Applications/Steam.app` only starts Steam. The client libraries live in:

```
~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/
```

Steam exports this path to compatibility tools as `STEAM_COMPAT_CLIENT_INSTALL_PATH`
(see [03](03-platform-and-launch.md)). Proton already builds `"$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamclient.dylib"`
on macOS.

## Evidence

```
$ lipo -detailed_info steamclient.dylib
architecture x86_64   size 26706832
architecture arm64    size 25493408

$ lipo -archs libtier0_s.dylib libvstdlib_s.dylib steam_osx
x86_64 arm64   (all three)

$ otool -arch x86_64 -l steamclient.dylib | grep -A3 LC_BUILD_VERSION
minos 11.0   sdk 26.2

$ codesign -dvv steamclient.dylib
Authority=Developer ID Application: Valve Corporation (MXGJJ98X76)
flags=0x0(none)
```

Dependencies of the x86_64 slice (`otool -arch x86_64 -L`): `@loader_path/` for `libtier0_s`, `libvstdlib_s`
and `libaudio`, plus system frameworks (AppKit, Carbon, Foundation, IOKit, OpenGL, OpenAL, CoreAudio,
Security, IOBluetooth…). Every system framework is universal.

## Conclusions

| Conclusion | Confidence |
|---|---|
| `steamclient.dylib` and its own dependencies (`libtier0_s`, `libvstdlib_s`, `libaudio`) have an x86_64 slice. x86_64 Wine under Rosetta can load them with `dlopen`. | High |
| No arm64 helper process with IPC is needed for milestone 5. | High (confirmed in milestone 5) |
| Wine does not use the hardened runtime, so library validation does not prevent loading a Valve-signed dylib. | High (confirmed in milestone 5) |
| The dylib links AppKit/Carbon. Loaded inside Wine (which uses AppKit through winemac.drv) it could compete for the main thread or `NSApplication`. | Medium (risk, not observed so far) |
