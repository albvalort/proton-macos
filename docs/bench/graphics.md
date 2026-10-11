# Gráficos (hito 3): resultados

Máquina: MacBook M2, macOS 27.0.1, Wine 11 x86_64 (Rosetta), MoltenVK 1.4.2, DXVK-macOS 1.10.3. Fecha: 2026-10-12.
Medición: `scripts/bench.sh` (HUD de Metal en el log del sistema, o la traza `+fps` de Wine), 30 s tras un
calentamiento, en el menú principal (escena repetible). Datos en bruto: [results.csv](results.csv).

| Juego | API | Backend (`PROTON_MAC_GFX`) | Camino | fps medios | mín. (1 s) |
|---|---|---|---|---|---|
| Downwell (360740) | D3D11 | `dxvk` | DXVK-macOS → MoltenVK → Metal | 60,0 | 60,0 |
| Downwell (360740) | D3D11 | `wined3d` | wined3d → OpenGL 4.1 | 59,7 | 58,3 |
| ANIMAL WELL (813230) | D3D12 | `dxvk` (*) | vkd3d de Wine → MoltenVK → Metal | 60,0 | 60,0 |
| — | D3D11/12 | `d3dmetal` | GPTK de Apple | pendiente | — |

(*) Con DXVK-macOS solo se sustituyen D3D10/11; D3D12 usa el `d3d12` de Wine (vkd3d) en cualquier backend salvo
`d3dmetal`.

Notas:

- Las dos cifras de 60 fps están limitadas por el vsync (pantalla de 60 Hz). Sirven como prueba de que funciona,
  no como comparación de rendimiento. El perfilado de verdad corresponde al hito 8.
- DXVK: feature level D3D11 11_0 en «Apple M2». vkd3d avisa de que faltan geometry shaders, stream output,
  cull distance y depth clip en MoltenVK. Afecta a algunos juegos DX12, no a ANIMAL WELL.
- El HUD de Metal puede dejar de registrar si el juego recrea la cadena de presentación (le pasó a Downwell
  con DXVK). Por eso `bench.sh` también recoge la traza `+fps` de Wine y se queda con la fuente que tenga más
  muestras.
- Pendiente de validación visual del usuario: que los dos juegos se vean bien y se puedan jugar.
