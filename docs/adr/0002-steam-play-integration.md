# ADR 0002: Integración con Steam a través de Steam Play (compatibilitytools.d)

- Estado: propuesta (validada con steamcmd; pendiente en el cliente gráfico)
- Fecha: 2026-10-11

## Contexto

El plan original del hito 9 era hookear dos cosas en una copia re-firmada de Steam.app: el chequeo de
plataforma (`oslist`) y el lanzamiento del juego. La investigación del hito 0
([03-platform-and-launch.md](../research/03-platform-and-launch.md)) demostró que:

- `CCompatManager` (Steam Play) está compilado en el cliente de Mac y solo lo desactiva
  `m_bEnabled = (oslist == "linux")`.
- Con ese booleano invertido en tiempo de ejecución, Steam registra una herramienta
  `from_oslist windows / to_oslist macos`, instala el depot de Windows y la lanza con
  `waitforexitandrun <exe>` y todas las `STEAM_COMPAT_*`.
- `steam_osx` no tiene hardened runtime, así que `DYLD_INSERT_LIBRARIES` funciona sin re-firmar.

## Decisión

- El producto es una **herramienta de compatibilidad estándar** en `compatibilitytools.d`, con el mismo
  contrato que en Linux. Funciona igual se instale como se instale.
- La integración con el cliente (hito 9) se limita a **invertir ese único chequeo** con un shim inyectado,
  sin modificar ficheros. Detecta el patrón por firma y se desactiva si no lo encuentra.
- Hasta que el hito 9 sea estable, el camino soportado es el launcher (`pmac`, hito 7) sobre steamcmd con
  el mismo shim, más accesos directos en la biblioteca.

## Consecuencias

- El hito 7 puede usar el propio Steam para descargar depots de Windows; DepotDownloader queda como plan B.
- Para que Valve lo adopte bastaría con cambiar una comparación, lo que hace la propuesta creíble.
- Riesgo: depender de un detalle interno del cliente. Mitigación: detección por firma y apagado seguro.
- Riesgo legal/de cuenta: modificar el comportamiento del cliente en tiempo de ejecución. Siempre opt-in,
  con advertencia y probado con cuentas secundarias.
