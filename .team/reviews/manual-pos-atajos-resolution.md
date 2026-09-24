# Resolución — revisión externa de los atajos por fila y el reparto del total

Informe: `.team/reviews/manual-pos-atajos-codex.md`
Commits: `ventago-app 522ba1f` (funcionalidad) · `6f2e62f8` (correcciones)

| # | Hallazgo | Severidad | Veredicto | Qué se hizo |
|---|---|---|---|---|
| 1 | Un pago del modal absorbe el cambio de total | Alta | **Aceptado** | `repartirCambioDeTotal` exige que el método esté en `ordenSlugs` |
| 2 | Dos filas pueden quedar con el mismo método | Media | **Aceptado** | `normalizarRanuras` al leer localStorage, al guardar y al reasignar |

## Por qué el 1 importa

El `indexOf` = -1 ordenaba esos pagos **al principio**, así que el bug sólo aparecía
cuando **ninguna** fila de la caja tenía plata. Es decir: cobro por cheque + efectivo,
y después agrego un producto → el cheque cambia solo. Un cheque tiene un importe
escrito en el papel; moverlo no es un detalle de UI.

## Por qué el 2 no era hipotético

`ventago.pos.pagoRanuras.v1` es del equipo, sin versión ni validación. Cualquier valor
viejo (o de una tienda con otros métodos, donde el slug ya no existe) llega tal cual.
Dos filas con el mismo slug editan **una sola línea** de pago.

## Nota de proceso

`codex exec` **muere en silencio (exit 0, salida vacía)** con prompts largos: el
primer intento de esta revisión nombraba 5 archivos y murió tras el primer paso de
razonamiento. El que funcionó nombra 2 archivos y pide lo mismo en tres renglones.
Ver memoria `codex-exec-dies-silently-on-big-prompt`.
