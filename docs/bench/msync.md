# msync: resultados

Máquina: MacBook M2, macOS 27.0.1, Wine x86_64 bajo Rosetta 2. Fecha: 2026-10-11.
Pruebas: `tests/msync/synctest.c` (correctness + tiempos), `tests/msync/opcost.c` (coste por llamada),
`tests/msync/ulock_bench.c` y `ulock_xproc.c` (primitivas). Medianas de 3 ejecuciones salvo indicación.

## Coste por operación sin contención (`opcost.exe`)

| Operación | Servidor (`WINEFSYNC=0`) | msync |
|---|---|---|
| `SetEvent` + `ResetEvent` | 19,36 µs | 3,82 µs |
| `WaitForSingleObject(e, 0)` + `SetEvent` | 20,71 µs | 4,12 µs |

## `synctest.exe` (x86_64)

| Prueba | Servidor | msync spin=0 | msync spin=1000 | **msync spin=4000** | msync spin=16000 |
|---|---|---|---|---|---|
| Ping-pong de eventos (µs/ida y vuelta) | 26,97 | 18,86 | 11,82 | **6,99** | 3,78 |
| WaitForMultiple *any*, 20k (ms) | 265 | 473 | 446 | **442** | 901 |
| WaitForMultiple *all*, 20k (ms) | 288 | 606 | 355 | **73** | 130 |
| Timeouts de 50 ms (ms) | 51 | 52 | 52 | **52** | 52 |
| Mutex con contención, 4×5000 (ms) | 209 | 65 | 63 | **37** | 35 |
| APC alertable (ms) | 34,5 | 37 | 37 | **40** | 40 |
| Ping-pong entre procesos (µs/ida y vuelta) | 31,6 | 25,2 | 16,6 | **9,4** | 7,6 |

Todas las pruebas pasan en todos los modos, también en el ejecutable de 32 bits (WoW64).

**Por defecto: spin=4000.** Con 16000 mejora algo más la latencia, pero se duplica el coste de WaitAny.

## Limitación conocida: productor libre + WaitAny

En *WaitForMultiple any*, el hilo productor hace `SetEvent` + `SwitchToThread` sin pausa. Con msync, cada vuelta
del productor cuesta unos 20 µs (en vez de unos 2), porque cada `SetEvent` despierta de verdad a un hilo
dormido, y en XNU bajo Rosetta ese despertar también le cuesta al que despierta. En modo servidor ese coste lo
paga el wineserver y el productor queda acompasado por la ida y vuelta al servidor. Es un patrón sintético; el
impacto real se medirá con juegos en el hito 8.

## Estabilidad

`tests/msync/stress.sh 30` (64 y 32 bits en bucle) se interrumpió a petición del usuario antes de los 30 minutos,
sin ningún fallo ni cuelgue registrado hasta ese momento. Además, Minimalism funcionó con msync activo.
**Pendiente:** completar la sesión de 30 minutos con un juego (criterio del hito 4).
