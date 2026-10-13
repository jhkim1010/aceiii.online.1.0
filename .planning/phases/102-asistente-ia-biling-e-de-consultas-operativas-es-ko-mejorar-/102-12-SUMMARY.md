---
phase: 102
plan: 12
status: complete
key-files:
  created: []
  modified: [.planning/intel/db-schema-tables.md, .planning/intel/db-schema-fks.md]
---

# 102-12 — Compuertas previas y migraciones en las dos bases

**Compuertas offline** (detalle en 102-12-GATES.md): api jest 276/276, app jest 27/27, tsc api/app 0,
eslint app limpio, api eslint sin hallazgos en líneas nuevas (8 previos a la fase).
CODEX en 4 trozos: 2 reales corregidos (api af44787c `ProbarRefuerzoDto.archivoDestino`, app a7027f6f cancelar reader),
3 falsos, 5 previos/opcionales anotados para planes futuros.

**Eval D-12 (modelo de producción qwen2.5:3b, timeout por defecto 60 s)**
`RESULTADO es 25/29 · ko 19/31 — inventa 0 — p50 23.9s p95 50.0s` — 2026-10-13 09:09–09:32 ART.
Corrida de día con `--ignorar-horario`: usuarios activos 2 (≤5, excepción de CLAUDE.md). 1 fila «error»
(es #19 «¿Cómo le fío a un cliente?», tope de 60 s). La línea base 22/31 (2026-10-11) usaba 120 s y 31 filas.

**Defecto encontrado al commitear** (gate de commit, store jest): `knowledge_refuerzos` no estaba en la cobertura de
respaldo / vaciado / eliminar. Corregido en api 800a3d35 (EXCLUDED / CONSERVAR / QUEDA, es conocimiento global).

**DDL** — aprobado por el usuario («승인»).
- Local 5432: aplicado 2026-10-13 ~09:29 ART (necesario para regenerar el inventario de respaldo).
- Producción 5434: aplicado 09:41 ART, usuarios activos medidos justo antes = 0.
  Verificación: `1|coolsistema|coolsistema`, índices pkey, uq_knowledge_refuerzos_activo, ix_knowledge_refuerzos_chat_message.
- Intel regenerado.

Sin push (plan 13).

## Self-Check: PASSED
