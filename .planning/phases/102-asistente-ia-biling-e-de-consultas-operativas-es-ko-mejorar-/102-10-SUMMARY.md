---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 10
subsystem: api-ventago / chat / knowledge
tags: [refuerzo, manual-sync, sin-respuesta]
requires: [102-06, 102-07, 102-16]
provides: [retirarRefuerzosFusionados in syncAll, sinRespuesta excludes reinforced questions]
key-files:
  modified:
    - api-ventago/src/app/chat/knowledge/manual-sync.service.ts
    - api-ventago/src/app/chat/knowledge/manual-sync.service.spec.ts
    - api-ventago/src/app/chat/chat.service.ts
  created:
    - api-ventago/src/app/chat/chat.service.sin-respuesta.spec.ts
requirements-completed: [D-09, D-10]
metrics:
  completed: 2026-10-12
---

# Phase 102 Plan 10: Cierre del ciclo de fuente unica Summary

`syncAll` retira (estado `fusionado` + borra `refuerzo/...`) los refuerzos cuya seccion ya existe en `manuales/`, y `sinRespuesta` excluye preguntas con refuerzo.

## Commits (api-ventago, nada pusheado)
- 3f1694f4: retiro en syncAll + 6 tests nuevos
- 01b06822: NOT EXISTS en sinRespuesta + spec (3 tests)

## Detalles
- Cableado: `ManualSyncService` esta en `chat.module.ts`, que ya registra `KnowledgeRefuerzo` en forFeature (plan 16). Modulo no tocado.
- El retiro corre solo dentro de `validSources.size > 0`; cada refuerzo en su transaccion (update + destroy) con try/catch; tambien limpia documentos `refuerzo/...` huerfanos de refuerzos ya fusionados. El orphan cleanup sigue limitado a `manuales/%` (test explicito).
- `syncAll` devuelve ahora `retirados` ademas de upserted/deleted.
- Verificacion: jest `src/app/chat` 20 suites / 211 tests verdes; tsc 0; eslint limpio en archivos nuevos.
- Mutaciones: (a) retirar sin chequear `validSources.has` -> falla el CONTROL (estado seguia 'activo'); (b) quitar el NOT EXISTS -> falla el spec de SQL. Ambas revertidas.

## Deviations from Plan
- Incidente menor: `git checkout` para revertir la mutacion (a) descarto tambien mis cambios sin commitear en manual-sync.service.ts; se restauraron desde copia de respaldo y se reverificaron los tests antes del commit.
- Warning de eslint preexistente en chat.service.ts:388 (no es de este plan).

## Notas
- `knowledge_refuerzos` sigue sin aplicar (plan 12); `sinRespuesta` falla en DB hasta entonces. No hubo push.

## Known Stubs
Ninguno.

## Self-Check: PASSED
