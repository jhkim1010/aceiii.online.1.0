---
phase: 96-notas-compartidas-del-local
plan: 10
status: deployed — browser verification (Task 4) pending user
completed: 2026-09-28
---

# 96-10 — Gate, producción, deploy

## Task 1 — Gate (todo verde)
- api `tsc --noEmit` exit 0 · app `tsc --noEmit` exit 0
- api jest `src/app/notas src/common/minio migration-conventions` → 7 suites, 183 passed (antes de los fixes CODEX); tras los fixes: 196 passed
- Selectores por decisión (cada uno ≥1 passed): visibility 16 · permission 34 · unread 13 · ack 19 · reads 14 · reaction 6 · reply 19 · edit|archive 18 · expiry 6 · attachment 13 · search 8 · tenant 6 · minio isPubliclyServable 8
- app jest notas-logic + sidebar-module-contract → 29 passed (31 tras fixes)
- eslint: archivos nuevos limpios. `minio.controller.ts` tiene 9 errores **preexistentes** (idénticos en origin/main).
- Greps de seguridad vacíos (los 2 `@Public` son comentario/nombre de test en el spec).
- Mutación D-05: M1 (quitar cláusula de destinatarios) → 3 fallan; M2 (quitar todo el predicado) → 6 fallan; revertido → verde.

## CODEX
- api `auto-api-ventago-f1a3cf93.md`: P1×3, P2×4, P3×1 → todos corregidos (ver `96-10-CODEX-FIXES.md`); rondas siguientes también corregidas; la última (`45eff50b`, verificación de FKs por definición) → «결함 없음».
- app `auto-ventago-app-743d409f.md`: P2×3, P3×2 → corregidos; seguimiento `f7ccd1a9`/`b5a2ca52`: P2×3, P3×1 → corregidos en `ventago-app@97e20c4d`.
- Riesgo residual aceptado: commit ambiguo (conexión cae justo después del COMMIT) puede duplicar una nota en reintento — requiere Idempotency-Key (fuera de alcance).

## Task 2/3 — Producción 5434 (aprobado por el usuario, 3 veces: SQL original, SQL modificado, recuento actualizado)
- Dry-run con ROLLBACK de ambos archivos → `p96 OK`, 10 restricciones OK, residuo `0|0|0`.
- Recuentos reales: ver-notas 132 · notas-enviar-todos 20 (la tienda 24 «Chic Cherry» se registró el mismo día → +6 roles, +1 admin respecto al primer conteo 126/19).
- Aplicado: tablas (exit 0, «10 restricciones … OK (por definición)») → permisos (exit 0, `p96 OK`). Verificación `7|coolsistema|2`; columnas prod 67 = local 67.
- Push: api `45eff50b` → Jenkins api-new-coolsistema #985 SUCCESS; app `b5a2ca52` → front-coolsistema #839 SUCCESS; contenedores recreados (api healthy).
- Smoke: `/api/notas/unread` 401, `/api/nota-adjuntos/1` 401; log `[perm] 103 slugs de @FunctionGuard, todos presentes en el catálogo`.
- Seguimiento app `97e20c4d` pusheado (build en curso al escribir esto).

## Desvío
- El ejecutor de 96-08 hizo `git push` pese a la instrucción (front #838 salió antes del seed). Sólo archivos nuevos, sin menú en prod → sin impacto. Memoria registrada.

## Task 4 — pendiente
Checklist de navegador presentado al usuario.
