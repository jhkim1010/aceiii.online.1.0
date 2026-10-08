---
phase: 101
plan: 13
subsystem: ventago-app
tags: [agente, modo-soporte, D-06, D-08, D-13, auth-context, with-access, sidebar]
requires: [101-10, 101-12]
provides:
  - decidirAccesoPantalla (puro)
  - itemsModoSoporte (puro)
  - superposicion de contexto de tienda en AuthContext
key-files:
  created:
    - ventago-app/src/configs/acceso-modo-soporte.ts
    - ventago-app/src/navigation/menu-modo-soporte.ts
    - ventago-app/src/__tests__/acceso-modo-soporte.spec.ts
    - ventago-app/src/__tests__/menu-modo-soporte.spec.ts
  modified:
    - ventago-app/src/context/AuthContext.tsx
    - ventago-app/src/context/types.ts
    - ventago-app/src/configs/withAccess.tsx
    - ventago-app/src/navigation/vertical/index.ts
metrics:
  tasks: 2
  completed: 2026-10-08
---

# Phase 101 Plan 13: Pantallas de la tienda en modo soporte Summary

El agente con grant `ver_*` ve la tienda del grant: AuthContext superpone `storeId/storeName/aliasName/logoUrl/structure` de `GET /agente/tienda/contexto` (roles siguen `['agent']`), WithAccess decide con ese structure y la barra lateral agrega el menu derivado.

## Commits (repo ventago-app)
- 314eb9b4: logica pura (decidirAccesoPantalla, itemsModoSoporte) + 2 specs
- e362f87a: cableado AuthContext / WithAccess / navigation/vertical

## Decisiones
- `aplicarModoSoporte(base)` corre tras `initAuth` y tras cada `refreshUser`; guarda el usuario base en un ref, de modo que salir del modo o un `AGENT_GRANT_REJECTED_EVENT` vuelve al base. Value del contexto sigue en useMemo; se agregaron `entrarModoSoporte/salirModoSoporte` (callbacks estables).
- WithAccess: `decidirAccesoPantalla` devuelve null sin modo con `ver_*` (logica anterior intacta); con modo ignora `allowedRoles`, cierra `superadminOnly`. `PRIVILEGED_ROLES`/`roles.ts` sin cambios (diff vacio).
- Barra lateral: `itemsModoSoporte` es un helper puro propio (no se extrajo la derivacion inline del hook, que depende de t/prefs/feAprobada); excluye `/caja`, `/control-de-caja`, `/nueva-venta` y `/dashboards*`, agrega Facturacion AFIP al app `venta` solo con `ver_facturas`.

## Deviations from Plan
- [Rule 3] El plan sugeria reutilizar/extraer la derivacion de la rama normal; es una clausura de ~250 lineas dentro del hook. Se escribio una derivacion minima pura en vez de refactorizar (cero riesgo para usuarios normales). Consecuencia: no aplica `menuPrefs` de la tienda, ni renombres/iconos del registro, ni el gating `requiereFe` de Facturacion AFIP en el menu del agente (el servidor igual decide).
- Se agrego un `sectionTitle` «Tienda en soporte» y el tipo `AuthValuesType` ganó dos miembros.
- Fuera del plan, 101-14 queda con el dialogo «El acceso terminó»; aqui solo se limpia el modo en `AGENT_GRANT_INVALID`.

## Verificacion
tsc exit 0; eslint exit 0 (archivos tocados); jest menu-modo-soporte, acceso-modo-soporte, menu-paths-exist, acceso-por-funcion, modo-soporte-logic exit 0. Greps de aceptacion = 1 cada uno. No se hizo prueba en navegador.

## Known Stubs
Ninguno.

## Self-Check: PASSED
