# ADR 0003: msync como backend de fsync sobre ulocks de XNU

- Estado: aceptada
- Fecha: 2026-10-11

## Contexto

El plan (hito 4) pedía portar msync de [marzent/wine-msync](https://github.com/marzent/wine-msync) (LGPL-2.1):
semáforos Mach y un servidor de mensajes Mach dentro del wineserver. Ese parche (2024) asume el modelo antiguo
del servidor de Wine, en el que cada objeto implementa `signaled` y expone su índice de sincronización. Al
aplicarlo sobre el Wine 11 de Valve fallan 45 fragmentos en 22 ficheros.

Wine 11 reorganizó la sincronización: los objetos delegan en objetos de sincronización (`get_sync`), y Valve
implementa **fsync como backend de la capa `inproc_sync`**, la misma que usa ntsync. fsync guarda todo el
estado en memoria compartida y solo necesita tres operaciones futex:

- despertar a todos los que esperan en una palabra;
- esperar en una palabra;
- esperar en varias a la vez (`futex_waitv`).

## Decisión

Implementar msync como **fsync con los futex emulados** sobre `__ulock_wait2`/`__ulock_wake` (XNU, macOS 11+,
la misma API que usan libc y libdispatch), en modo `UL_COMPARE_AND_WAIT_SHARED`, que funciona entre procesos.

- Espera en una palabra → `__ulock_wait2`.
- Despertar → `__ulock_wake(ULF_WAKE_ALL)`, más un contador de época compartido.
- Espera en varias palabras → registro en un bloque de control (índice 0 de la memoria compartida, que fsync
  nunca asigna), lectura de la época, comprobación de las palabras y espera sobre la época. Con atomics
  secuencialmente consistentes no se pierde ningún despertar. Los despertares espurios no importan, porque
  fsync siempre vuelve a comprobar los objetos.
- Espera activa acotada antes de dormir (`WINE_MSYNC_SPIN`, 4000 iteraciones por defecto): despertar un hilo
  bloqueado en el kernel cuesta varios µs en Apple Silicon bajo Rosetta.
- Plazo ya vencido → comprobar y devolver sin entrar en el kernel (un ulock con timeout mínimo sigue armando
  un temporizador agrupado de decenas de µs).
- Memoria compartida con `shm_open` y un único `ftruncate` a 64 MiB, porque en macOS los objetos shm no se
  pueden redimensionar. Las páginas solo se materializan al usarse.
- `inproc_sync` del servidor se compila en macOS en modo «solo fsync», sin ntsync.

Activación: `WINEFSYNC=1`, que el script `proton` pone por defecto en macOS. Se desactiva con
`PROTON_NO_MSYNC=1`, con el mismo patrón que `PROTON_NO_FSYNC`.

## Consecuencias

- Unas 150 líneas en cinco ficheros (`include/wine/darwin_futex.h`, `server/fsync.c`, `server/inproc_sync.c`,
  `dlls/ntdll/unix/fsync.c`, `include/Makefile.in`), frente a unas 5000 del parche original. Todo el modelo de
  objetos de fsync, ya probado por Valve, se reutiliza tal cual.
- Depende de una API privada pero estable de XNU (`__ulock_*`), que usa el propio sistema.
- La espera múltiple despierta a todos los que esperan en varias palabras ante cualquier despertar. Es correcto,
  pero escala peor con muchos hilos en esperas múltiples. Si un juego lo sufre, el siguiente paso es repartir la
  época en *buckets* por dirección.
- Diferencia con el msync de marzent: no hay servidor de mensajes Mach. Las esperas no pasan nunca por el
  wineserver.
- Resultados y metodología en [docs/bench/msync.md](../bench/msync.md).
