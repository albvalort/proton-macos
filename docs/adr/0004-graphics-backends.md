# ADR 0004: Backends gráficos en macOS

- Estado: aceptada (los tres backends funcionan; D3DMetal validado con GPTK 4.0 beta 2)
- Fecha: 2026-10-11

## Contexto

En Linux, Proton traduce D3D9/10/11 con DXVK y D3D12 con vkd3d-proton, ambos sobre Vulkan. En macOS hay
cuatro opciones:

| Opción | API cubiertas | Requisito | Problema |
|---|---|---|---|
| wined3d (de Wine) | D3D1–11, D3D12 parcial con vkd3d | OpenGL 4.1 (o Vulkan) | Lento y con poca cobertura de D3D11 sobre GL 4.1 |
| DXVK sobre MoltenVK | D3D10/11 | MoltenVK (universal, Apache-2.0) | DXVK 2.x exige extensiones que MoltenVK no tiene; hay que usar el fork macOS de Gcenx (DXVK 1.10.3, zlib), igual que CrossOver |
| DXVK 2.x / vkd3d-proton sobre **KosmicKrisp** | D3D9–12 | KosmicKrisp (Mesa sobre Metal 4, conforme con Vulkan 1.4 y listo para producción según [LunarG, oct. 2026](https://www.lunarg.com/the-state-of-vulkan-on-apple-oct-2026/)) | **Solo arm64**: no se puede cargar en un proceso x86_64 bajo Rosetta, como es nuestro Wine |
| D3DMetal (GPTK de Apple) | D3D11/12 | Que el usuario instale GPTK | No se puede redistribuir. La licencia limita su uso a evaluar ports. El ABI de sus módulos unix debe coincidir con nuestra versión de Wine |

## Decisión

- `PROTON_MAC_GFX=dxvk|d3dmetal|wined3d` en el script `proton`. Por defecto: **dxvk** si está empaquetado; si
  no, wined3d. `d3dmetal` es siempre opt-in y solo funciona si se detecta GPTK (`PROTON_MAC_GPTK`,
  `~/Library/Application Support/proton-macos/gptk/*/redist/lib` o el entorno de evaluación montado). Sus
  módulos se enlazan en `<compatdata>/gptk/` y se buscan antes que los de Wine (`WINEDLLPATH_PREPEND`). No se
  copia nada de Apple. Integración en Wine portada de CrossOver: ver `docs/patches/wine.md`. Solo x86_64 (GPTK
  no trae módulos de 32 bits).
- DXVK-macOS 1.10.3 (Gcenx, zlib) aporta `d3d11`/`d3d10core`. `dxgi`, `d3d9` y `d3d12` son los de Wine, este
  último con vkd3d sobre winevulkan → MoltenVK.
- Wine se compila con Vulkan contra MoltenVK 1.4.2 (binario oficial universal, que se empaqueta junto a Wine).
- **KosmicKrisp:** no se integra por ahora (no hay selector implementado), porque no puede funcionar con Wine
  x86_64. Haría falta el lado unix de Wine en arm64, con los PE x86 traducidos por otro
  mecanismo, o renderizado fuera de proceso. Se revisará si LunarG publica un slice x86_64.

## Consecuencias

- DX12 sin GPTK depende de vkd3d (no vkd3d-proton) sobre MoltenVK: compatibilidad limitada.
- Para DX12 serio, D3DMetal es hoy la única vía, y queda en manos del usuario y de la licencia de Apple.
- Benchmarks por backend en `docs/bench/` (hito 3).
