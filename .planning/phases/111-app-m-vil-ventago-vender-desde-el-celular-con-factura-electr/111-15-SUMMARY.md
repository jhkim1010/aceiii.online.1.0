---
phase: 111-app-m-vil-ventago-vender-desde-el-celular-con-factura-electr
plan: 15
subsystem: api-ventago/mobile
tags: [devices, guards, colibri, terminal, revocation]
requires: ["111-01", "111-03", "111-18"]
provides:
  - MobileDevicesService (register/status/list/approve/revoke/rename/resolveApproved)
  - MobileTerminalGuard (req.device from the approved device)
  - MobileDevicesModule exporting MobileTerminalGuard + MobileScopeGuard
key-files:
  created:
    - api-ventago/src/app/mobile/devices/ (module, service, 2 controllers, service spec)
    - api-ventago/src/app/mobile/guards/mobile-terminal.guard.ts (+ spec)
    - api-ventago/src/app/session/session.service.terminal-movil.spec.ts
  modified:
    - api-ventago/src/app/mobile/guards/mobile-scope.guard.ts (+ spec)
    - api-ventago/src/app/mobile/pos/mobile-pos.module.ts
    - api-ventago/src/app/mobile/pos/shared/pos-request.ts
    - api-ventago/src/app/session/session.service.ts, session.module.ts
decisions:
  - Cache of the terminal guard stores only approved results (getOrLoad shouldCache); approve/revoke clear the key after commit
  - Revocation is immediate through deletion of mobile_sessions in the same tx (MobileScopeGuard reads them uncached)
metrics:
  completed: 2026-10-16
  api-commit: 5f1659eb
---

# Phase 111 Plan 15: Dispositivos moviles aprobados Summary

El celular Colibri se registra como pendiente, un encargado con editar-terminal/update lo aprueba en una caja de su tienda (crea una fila en terminals), y MobileTerminalGuard resuelve terminal/caja/sucursal solo desde ese dispositivo; la baja borra sus mobile_sessions en la misma transaccion.

## Que se hizo
- `POST /mobile/pos/device/register`, `GET /mobile/pos/device/status` (JWT + MobileScopeGuard, sin guard de terminal; huella solo de `req.mobileSession`).
- `GET/POST/PATCH /mobile/devices[/:id/approve|revoke]` con `@FunctionGuard('editar-terminal','update')` x4 y `@Audit` (sin DML de permisos, sin nota perm-cache).
- `moveToTerminalAndCreateSession` lanza 409 `TERMINAL_MOVIL` si la terminal pertenece a un celular no revocado (control: terminal comun sigue).
- `MobileScopeGuard` expone `req.mobileSession` (cambio aditivo). `pos-request.ts`: `mobileSession.id` pasa a `string` (es uuid) y se agrega `deviceFingerprintOf()`.

## Verificacion
- jest `src/app/mobile/guards src/app/mobile/devices src/app/session`: 36 tests verdes (service 12, terminal guard 13, scope guard + 3 nuevos, session TERMINAL_MOVIL 2). tsc 0, eslint limpio, gate del commit paso.
- `src/app/auth/guards`: 133 verdes, 3 fallos preexistentes de agent-readonly-scopes.venta.spec.ts (no mios). No hizo falta tocar manifiestos de enumeracion.
- Mutaciones (ambas compilaron, no "Tests: 0"):
  - quitar igualdad userId: mato "JWT de A + sesion de B -> DEVICE_UNKNOWN; control: mismo usuario pasa".
  - quitar storeId de `resolveApproved`: 12 tests fallan (incl. "misma huella en OTRA tienda" y los where con storeId).
  Ambos restaurados (diff contra copia = vacio).

## Deviations from Plan
- **Un solo commit para ambas tareas** (5f1659eb): MobileDevicesModule importa MobileTerminalGuard y este usa MobileDevicesService, asi que separarlos dejaba un commit que no compila.
- **[Rule 1]** `mobileSession.id` tipado `number` en pos-request.ts era incorrecto (uuid); corregido a `string`.
- Test "register con fila revocada" verifica que la consulta excluye `revoked` (operador `Op.ne`) y que crea una fila nueva.

## Notas
- No se hizo push (Plan 14 publica en orden). STATE.md / ROADMAP.md quedan sin commitear a proposito.
- Requiere la tabla `mobile_devices` (migracion Phase 111 del Plan 01) aplicada antes de desplegar; los specs usan modelos simulados.
- Sin DDL/DML de produccion en este plan.

## Self-Check: PASSED
Commit 5f1659eb existe en api-ventago; archivos creados presentes.
