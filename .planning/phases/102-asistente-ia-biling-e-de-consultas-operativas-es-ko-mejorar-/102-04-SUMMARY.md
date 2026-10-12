---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 04
subsystem: ventago-app / chat
tags: [refuerzo, manual, superadmin, mui]
requires: []
provides: [refuerzoForm pure logic, RefuerzoDialog, Responder button]
affects: [ventago-app/src/components/chat]
tech-stack:
  added: []
  patterns: [pure logic in .ts + presentation in .tsx]
key-files:
  created:
    - ventago-app/src/components/chat/refuerzoForm.ts
    - ventago-app/src/__tests__/refuerzo-form.spec.ts
    - ventago-app/src/components/chat/RefuerzoDialog.tsx
  modified:
    - ventago-app/src/components/chat/PreguntasSinRespuesta.tsx
key-decisions:
  - "Spec placed in src/__tests__/ (app jest ignores specs elsewhere)"
metrics:
  completed: 2026-10-12
---

# Phase 102 Plan 04: Refuerzo de manual UI Summary

Dialogo de refuerzo (responder, vista previa editable con titulo sugerido, probar es/ko, guardar con bloqueo por seccion parecida) y boton «Responder» en «Preguntas sin respuesta», con la logica pura probada.

## Commits (ventago-app, nada pusheado)
- 296fd28b: refuerzoForm.ts + spec
- 83e4e108: RefuerzoDialog.tsx + boton Responder

## Verificacion
- jest refuerzo-form.spec.ts: 11 passed (el plan pedia >=13; los casos del behavior estan todos cubiertos en 11 tests agrupados).
- Mutaciones: (a) cuerpoGuardar con `contenido: estado.texto` -> 1 failed; (b) quitar el chequeo `parecida && !temaDistinto` -> 1 failed; ambas revertidas, 11 verdes.
- tsc --noEmit sin errores; eslint --max-warnings=0 limpio. Sin `next build`.

## Deviations from Plan
- [Rule 3] El spec va en `ventago-app/src/__tests__/refuerzo-form.spec.ts`, no en `components/chat/` (jest solo toma `__tests__`).
- El diálogo se divide en `RefuerzoDialog` + componente interno `Contenido` con `key=fila.id` para reiniciar estado por fila.

## Known Stubs
Ninguno. Depende de endpoints /chat/refuerzos* de los planes 07/16 (aun no desplegados); verificacion visual en plan 13.

## Self-Check: PASSED
