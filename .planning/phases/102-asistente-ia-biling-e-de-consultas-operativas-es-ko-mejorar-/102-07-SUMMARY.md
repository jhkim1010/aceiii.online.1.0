---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 07
subsystem: api-ventago / chat / knowledge
tags: [refuerzo, manual, knowledge_refuerzos, tenant, migration]
requires: [102-01, 102-02, 102-06]
provides: [knowledge_refuerzos table (SQL only), KnowledgeRefuerzo model, refuerzo-reglas, RefuerzoService]
affects: [api-ventago/src/app/chat/knowledge]
key-files:
  created:
    - api-ventago/migrations/2026-10-12-knowledge-refuerzos.sql
    - api-ventago/src/app/chat/knowledge/refuerzo.model.ts
    - api-ventago/src/app/chat/knowledge/refuerzo.tenant.spec.ts
    - api-ventago/src/app/chat/knowledge/refuerzo-reglas.ts
    - api-ventago/src/app/chat/knowledge/refuerzo-reglas.spec.ts
    - api-ventago/src/app/chat/knowledge/refuerzo.service.ts
    - api-ventago/src/app/chat/knowledge/refuerzo.service.spec.ts
  modified:
    - api-ventago/src/app/chat/knowledge/knowledge.service.ts
key-decisions:
  - "Tenant registry unchanged: a model without storeId is not guarded by convention (resolveModelPolicy); no spec enumerates models. Pinned by refuerzo.tenant.spec with a control."
  - "upsertDocument gained optional opts.transaction (callers unchanged)."
  - "Stored slug is always slugify(titulo as received); no slug from the client."
metrics:
  completed: 2026-10-12
---

# Phase 102 Plan 07: Refuerzo backend Summary

Tabla `knowledge_refuerzos`, reglas puras (formato, titulo sugerido/aceptable, parecida, archivos permitidos) y `RefuerzoService` con preview es/ko, probar sin escribir, guardar transaccional (400/409 por `motivo`) y listar.

## Estado de la migracion

**NO aplicada en ningun lado** (ni local 5432 ni produccion 5434): solo el archivo SQL `2026-10-12-knowledge-refuerzos.sql`. Se aplica en el plan 12, antes del push del plan 13. **Nada pusheado, produccion intacta.** El modelo no esta registrado aun en `ChatModule` (`SequelizeModule.forFeature`) ni hay controller: es el plan 16.

## Commits (api-ventago)
- af605f5b: migracion + modelo + spec de tenant
- 6bfa866a: refuerzo-reglas + spec
- 15720a29: RefuerzoService + spec + `upsertDocument(…, {transaction})`

## Verificacion
- jest `src/app/chat src/common/migrations src/common/tenant tenant-guard-coverage`: 24 suites / 249 tests verdes; tsc exit 0; eslint --max-warnings=0 limpio en los archivos nuevos.
- refuerzo.tenant.spec: 4 tests (guarded=false, allowGlobalRows=false, sin regla derivada, sin storeId, control con modelo con store_id).
- refuerzo-reglas.spec: 16 tests. Mutaciones: (a) archivosPermitidos sin excluir soporte_remoto_ko.md -> 1 falla; (b) tituloAceptable siempre true -> 1 falla (control verde). Revertidas.
- refuerzo.service.spec: 25 tests. Mutaciones: (a) sin chequeo contra sourceDeManual -> falla titulo_existente; (b) sin chequeo de parecida -> fallan 2 tests; (c) `!!temaDistinto` -> falla el test de `'true'`; (d) sin release del slot -> fallan 2 tests. Todas revertidas, 25 verdes.
- `tenant-scope.registry.ts`: **sin cambios** (modelo sin storeId = no guarded por convencion).

## Deviations from Plan
- [Rule 3] El spec de tenant usa un modelo de control local con la forma de ChatMessage (storeId) en vez de importar ChatMessage: importarlo arrastra las asociaciones de Users y Sequelize falla al montarlo sin los demas modelos.
- Tests de service: 25 (>= 19); reglas: 16 (>= 14).
- `probar` acepta `archivoDestino` opcional (el contrato del plan 04 no lo envia; por defecto manual_ventas.md solo para el source del borrador).

## Known Stubs
Ninguno.

## Self-Check: PASSED
