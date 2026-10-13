---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 09
subsystem: chat/knowledge
tags: [manuales, busqueda, ko-es, eval]
requires: [102-05]
provides: [manuales reforzados, tabla K-T, minimos de busqueda es 25 / ko 26]
affects: [api-ventago/manuales, terminos-ko-es.ts, preguntas-asistente.spec.ts]
key-files:
  modified:
    - api-ventago/manuales/manual_producto.md (nueva seccion 11 Redondeo + sinonimos F5)
    - api-ventago/manuales/manual_ventas.md (F1, F2)
    - api-ventago/manuales/credito_senia_favor.md (F3, F4)
    - api-ventago/manuales/manual_stock.md (F6, F7)
    - api-ventago/manuales/manual_talleres.md (F8)
    - api-ventago/manuales/manual_materiaprima.md (F9)
    - api-ventago/src/app/chat/knowledge/terminos-ko-es.ts (10 entradas K-T)
    - api-ventago/src/app/chat/eval/preguntas-asistente.spec.ts (minimos)
decisions:
  - R1 aplicada tal cual (nombres de menu y frase de permisos del borrador, sin agregar permisos)
  - F1 con «tarjeta», F8 con «confeccion»
  - K-T aprobada, incluida 반올림/올림 -> redondeo, precio
  - K0 NO aprobada: sin respuesta fija ni cambio de producto
  - K10 sin resolver; soporte_remoto_ko.md intacto (D-06)
metrics:
  completed: 2026-10-13
---

# Phase 102 Plan 09: Manuales reforzados y minimos de busqueda Summary

Se integraron al manual los borradores aprobados por el usuario (redondeo de precios y cotizacion, sinonimos coloquiales F1-F9) y las entradas K-T de la tabla ko->es, subiendo los minimos de la prueba de busqueda a los valores medidos.

## Decisiones del usuario (respuesta «진행» = aprobar todo)
1. R1: se mantienen los nombres de menu del borrador («Precios», «Configuración → Productos»).
2. R1: frase de permisos exactamente como el borrador (sin agregar/quitar).
3. F1: «tarjeta» como ejemplo.
4. F8: se incluye «confección».
5. K-T aprobada (terminos-ko-es.ts), re-agregando 반올림->redondeo.
6. K0 NO aprobada. K10 queda sin resolver (D-06).

## Medicion (busqueda sin modelo)
| Idioma | Antes | Despues | Minimo |
|---|---|---|---|
| es | 17/26 | 25/26 | 17 -> 25 |
| ko | 18/28 | 26/28 | 18 -> 26 |

Fallos restantes: es «¿Cómo cargo un artículo nuevo?» (la busqueda sigue priorizando Nueva Venta; arreglarlo requeriria bajar el peso de «artículo», no tocado); ko K6 (la seccion de redondeo le gana a Gestion de precios) y K10 (soporte remoto ko).

## Verificacion
- jest `chat/eval` + `chat/knowledge`: 10 suites, 112 tests verdes (incluye la prueba anti-typo: todo destino espanol de K-T existe en algun manual).
- Mutacion: con la tabla K-T original (sin las 10 entradas) el test «aciertos ko >= minimo» falla (Received 18, Expected >= 26); restaurada vuelve a verde.
- ESLint sin warnings en los dos .ts. `soporte_remoto_ko.md` sin cambios.

## Commits
- api-ventago `978e1e64`: feat(102-09) manuales + K-T + minimos. (Task 1: `aafe9c9` en repo raiz.)
- Nada pusheado (push = plan 13).

## Deviations from Plan
- Se toco `terminos-ko-es.ts` (fuera de `files_modified`) con aprobacion explicita del usuario. `manual_admin.md`, `venta_a_credito.md` y `cobro_credito.md` no necesitaron cambios.

## Known Stubs
None.

## Self-Check: PASSED
