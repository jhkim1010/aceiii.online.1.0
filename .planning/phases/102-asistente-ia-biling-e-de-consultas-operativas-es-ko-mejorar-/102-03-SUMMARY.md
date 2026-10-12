---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 03
subsystem: ventago-app/chat
tags: [streaming, ndjson, fetch, asistente]
requires: []
provides:
  - chatStream.ts (leerNdjson, aplicarEvento, conParcial, conFinal)
  - askAssistantStream (unico punto de llamada, fallback a POST)
  - buildAuthHeaders / API_BASE_URL en api.service.ts
affects: [102-06, 102-13]
key-files:
  created:
    - ventago-app/src/components/chat/chatStream.ts
    - ventago-app/src/__tests__/chatStream.spec.ts
  modified:
    - ventago-app/src/services/api.service.ts
    - ventago-app/src/components/chat/chatAnswer.ts
    - ventago-app/src/components/chat/ChatWindow.tsx
    - ventago-app/src/views/manuales/ManualesView.tsx
    - ventago-app/src/__tests__/menu-chat-entradas.spec.ts
decisions:
  - "Fallback al POST clasico solo antes del primer byte; despues se devuelve lo acumulado"
  - "Headers de fetch y axios salen de una sola funcion buildAuthHeaders()"
metrics:
  tasks: 2
  commits: "ventago-app d7eb164f, da34e44e"
  completed: 2026-10-12
---

# Phase 102 Plan 03: Cliente de streaming del chat Summary

Parser NDJSON puro con buffer de lineas, reductor donde el evento final reemplaza el parcial, y `askAssistantStream` (fetch a `/chat/message/stream`, timeout 90 s) con fallback a `askAssistant` ante 404/401/5xx/red antes de recibir bytes. ChatWindow y ManualesView pintan el texto progresivo.

## Commits (ventago-app, nada pusheado)
- d7eb164f parser + reductor + spec
- da34e44e buildAuthHeaders, askAssistantStream, consumidores

## Verificacion
- jest chatStream + menu-chat-entradas: 13 passed (chatStream 10); tsc exit 0; eslint 0 warnings en los archivos tocados.
- Mutacion: sin buffer de resto en leerNdjson -> fallan 3 tests (linea partida, linea final, hangul partido). Revertido.
- Verificacion real a traves de nginx queda para el plan 13.

## Deviations from Plan
- [Rule 3] El spec vive en `src/__tests__/chatStream.spec.ts` (no junto al componente): el `testMatch` de jest del app solo toma `**/__tests__/**`, en el otro lugar jamas correria.
- [Rule 3] `menu-chat-entradas.spec.ts`: su regex `\baskAssistant\(` no reconocia `askAssistantStream(`; se amplio para que /manuales siga contando como chat.
- Se agregaron `conParcial`/`conFinal` (puros, en chatStream.ts, con tests) para la actualizacion funcional de mensajes y el flag `streaming` en el `Message` de ambos consumidores; el spinner "Pensando" se oculta cuando ya hay texto.
- `x-api-key` se incluye en buildAuthHeaders (era header por defecto de axios; fetch no lo hereda).

## Known Stubs
None.

## Self-Check: PASSED
