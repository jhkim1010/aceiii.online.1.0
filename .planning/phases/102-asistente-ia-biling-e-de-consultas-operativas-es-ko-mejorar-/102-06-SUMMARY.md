---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 06
subsystem: api-ventago/chat
tags: [streaming, ndjson, migration, asistente]
requires: ["102-02"]
provides:
  - POST /chat/message/stream (NDJSON meta/delta/final)
  - ChatService.prepararPregunta / generarRespuesta / procesarStream, EventoChat
  - chat_messages.meta jsonb (migracion escrita, NO aplicada)
  - SendMessageDto (max 1000)
affects: [102-07, 102-12, 102-13]
key-files:
  created:
    - api-ventago/migrations/2026-10-12-chat-messages-meta.sql
    - api-ventago/src/app/chat/dto/send-message.dto.ts
    - api-ventago/src/app/chat/chat.controller.stream.spec.ts
  modified:
    - api-ventago/src/app/chat/chat.model.ts
    - api-ventago/src/app/chat/chat.service.ts
    - api-ventago/src/app/chat/chat.service.asistente.spec.ts
    - api-ventago/src/app/chat/chat.service.references.spec.ts
    - api-ventago/src/app/chat/chat.controller.ts
    - api-ventago/src/app/chat/chat.controller.roles.spec.ts
decisions:
  - "Abort via res.on('close') con guarda writableFinished (no req 'close')"
  - "C-<id> es solo referencia de consulta; el flujo HMAC de soporte no cambia"
metrics:
  tasks: 3
  commits: "api-ventago 083b5aa0, 412cb9f3, 1ec44092"
  completed: 2026-10-12
---

# Phase 102 Plan 06: Servidor del streaming y meta Summary

Un solo flujo con dos salidas: `processMessage` (buffer) y `procesarStream` (NDJSON) comparten `prepararPregunta` y la limpieza; el stream pasa por `PuertaDeStream`, aplica el recorte D-16 con `C-<id>` y cada respuesta guarda `meta`.

## Estado de la migracion (importante)
`api-ventago/migrations/2026-10-12-chat-messages-meta.sql` esta ESCRITA y commiteada pero **NO aplicada en ningun lado** (ni local 5432 ni produccion 5434). Se aplica en el plan 12 antes del push del plan 13. Hasta entonces el modelo tiene la columna `meta` y cualquier chat contra una DB sin ella daria 500: no ejecutar el API contra la DB local hasta aplicarla. **Nada pusheado.**

## Verificacion
- `npx jest src/app/chat`: 141 passed; migration-conventions: 9 passed; tsc exit 0.
- Mutacion: emitir tokens sin PuertaDeStream -> falla 'NO,_ENCONTRADO' por valor; quitar recortarAUltimaFrase -> falla D-16; quitar `!res.writableFinished` -> falla el control de close tras end. Todas revertidas.

## Deviations from Plan
- [Rule 3] `chat.service.references.spec.ts` (no listado) recibio `modelo()` en su mock de llmFactory porque processMessage ahora lo llama.
- El test de codigo de soporte por stream usa el texto real del spec existente (el primer intento era vacuo).
- eslint de chat.controller.ts reporta `getSyncStatus` require-await (preexistente, no tocado).

## Known Stubs
None.

## Self-Check: PASSED
