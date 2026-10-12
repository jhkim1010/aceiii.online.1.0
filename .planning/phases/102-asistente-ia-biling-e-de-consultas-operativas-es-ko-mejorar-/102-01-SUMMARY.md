---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 01
subsystem: chat/knowledge
tags: [asistente, busqueda, ko-es]
requires: []
provides:
  - "TERMINOS_KO_ES / expandirKo (tabla estática ko→es)"
  - "keywordsOf expandido; manualLabelOf reconoce refuerzo/"
affects: [api-ventago/src/app/chat/knowledge]
key-files:
  created:
    - api-ventago/src/app/chat/knowledge/terminos-ko-es.ts
    - api-ventago/src/app/chat/knowledge/terminos-ko-es.spec.ts
  modified:
    - api-ventago/src/app/chat/knowledge/knowledge-search.ts
    - api-ventago/src/app/chat/knowledge/knowledge-search.spec.ts
decisions:
  - "Tabla estática determinística (sin LLM) para la búsqueda ko→es"
  - "Entrada 반올림→redondeo eliminada: ningún manual usa esa palabra (control anti-typo)"
metrics:
  completed: 2026-10-12
  tasks: 2
---

# Phase 102 Plan 01: Búsqueda coreano→español Summary

Tabla estática de términos coreanos→españoles que `keywordsOf()` suma a las keywords, de modo que preguntas coreanas de gestión (재고, 가격, 보고서, 외주, 원단...) encuentran secciones de los manuales en español; `manualLabelOf()` reconoce el prefijo `refuerzo/`.

## Commits (api-ventago, sin push)
- bc5c9e60: tabla + expandirKo + spec (7 tests)
- 635231f9: keywordsOf/manualLabelOf + specs ampliados

## Verificación
- jest knowledge + eval: 5 suites, 37 tests verdes; eval sigue en 19/28 (sin regresión)
- tsc --noEmit exit 0; eslint sin avisos
- Mutaciones (revertidas): palabra 'xyzinexistente' en una entrada → anti-typo falla (1 fallo); expandirKo siempre [] → 3 fallos
- soporte_remoto_ko.md no tocado

## Deviations from Plan
1. [Rule 1 - Bug] El control anti-typo detectó 'existencia' y 'redondeo' ausentes de los manuales: 'existencia' → 'unidades' (existe en manual_stock); la entrada 반올림→redondeo se eliminó (ningún manual habla de redondeo; si se agrega en el plan 09, reponer).
2. Test existente `keywordsOf('판매를 하려면?')` pasó de `['판매']` a `['판매','vent']`: es el comportamiento nuevo buscado.

## Known Stubs
None.

## Self-Check: PASSED
