---
phase: 101
plan: 14
subsystem: ventago-app
tags: [agente, modo-soporte, D-06, D-08, D-09, swr, banner]
requires: [101-12, 101-13]
provides:
  - useModoSoporte
  - swrAgenteMiddleware (global, SwrConfigProvider)
  - ModoSoporteBanner / SinAlcance / AccesoTerminadoDialog
key-files:
  created:
    - ventago-app/src/hooks/useModoSoporte.ts
    - ventago-app/src/components/agente/ModoSoporteBanner.tsx
    - ventago-app/src/components/agente/SinAlcance.tsx
    - ventago-app/src/components/agente/AccesoTerminadoDialog.tsx
    - ventago-app/src/__tests__/modo-soporte-swr.spec.ts
  modified:
    - ventago-app/src/services/modo-soporte-logic.ts
    - ventago-app/src/services/agent-grant.ts
    - ventago-app/src/hooks/useApi.ts
    - ventago-app/src/lib/swr-config.tsx
    - ventago-app/src/layouts/UserLayout.tsx
metrics:
  tasks: 2
  completed: 2026-10-08
---

# Phase 101 Plan 14: Capa visible del modo soporte Summary

Banner fijo de 48 px con contador, componente SinAlcance, dialogo no descartable «El acceso terminó» y un middleware SWR global que vuelve no fatal el 403 de alcance en todo `useSWR` del arbol.

## Commits (repo ventago-app)
- cee817f1: useModoSoporte, logica pura (estadoContador, resultadoSwrAgente, noReintentarAgente, esSinAlcance, swrAgenteMiddleware), SwrConfigProvider (`use` + `onErrorRetry`), useApi, evento `ventago:modo-soporte` en setModoSoporte, spec nuevo
- b117639d: ModoSoporteBanner, SinAlcance, AccesoTerminadoDialog, montaje en UserLayout

## Decisiones
- El middleware devuelve el MISMO objeto de SWR salvo en el 403 de alcance (spec con control de identidad `toBe`). dedupingInterval y demas config intactos; los hooks con useSWR directo no se editaron.
- `onErrorRetry` replica el backoff exponencial por defecto de SWR y omite el reintento para alcance / GRANT_INVALID.
- Spec nuevo `modo-soporte-swr.spec.ts` (el spec existente `modo-soporte-logic.spec.ts` es de 101-12 y se dejo intacto).
- Reserva de 48 px: `--modo-soporte-h` en `:root` + `GlobalStyles` (solo con banner visible) que da `padding-top` a `.layout-wrapper` y desplaza `.layout-vertical-nav`. No se tocaron los useCallback/useMemo de UserLayout.
- El banner se muestra solo si el modo es `soloLectura` (todos los alcances ver_*); con alcances mixtos (ver_* + legacy) no aparece.
- Salir: `salirModoSoporte()` + `/admin/agente`; «Volver a Usar código» ademas limpia el modo.

## Deviations from Plan
- UI-SPEC menciona `/agente/acceso`; se uso `/admin/agente` como indica el plan.
- `useApi` ahora devuelve siempre `sinAlcance` (false para usuarios normales) en vez de campo ausente; mismo comportamiento para el resto de campos.
- El snackbar `info` de UI-SPEC para 403 de alcance no se agrego (fuera de las tareas del plan).

## Verificacion
jest modo-soporte-swr + modo-soporte-logic exit 0; tsc exit 0; eslint exit 0 en archivos tocados. No se probo en navegador (101-18).

## Known Stubs
Ninguno. 101-16 consume `esSinAlcance` / `SinAlcance` en Ventas, Productos y Sucursales.

## Self-Check: PASSED
