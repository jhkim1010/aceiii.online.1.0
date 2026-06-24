# Transportes en Configuración de Ventas — Design

**Fecha:** 2026-06-24
**Estado:** Aprobado (diseño)

## Objetivo

Exponer la gestión de **Transportes** (transportistas/medios de envío) como una tarjeta
siempre visible en la pantalla de **Configuración › Ventas**, y sembrar dos valores
iniciales para todas las tiendas: **"Correo Argentino"** y **"Por su propia cuenta"**.

## Contexto / lo que ya existe (Phase 42)

El backend de Transporte ya está completamente implementado:

- Tabla `transportes` (`store_id`, `name`, `is_active`) — store-scoped.
- Modelo / servicio / controlador: `GET /transportes`, `POST /transportes`, `PUT /transportes/:id`
  (toggle `isActive`, sin hard-delete). `storeId` se inyecta del JWT.
- Hook frontend `useTransportes()` (SWR, dedup 5 min).
- Componente `TransporteCard` (tema **oscuro**, navy+gold) usado en `/configuracion/envios`,
  detrás del toggle "Modo envíos" (`useEnvios`).

**No se necesita backend CRUD nuevo.** Se reutilizan endpoints + hook.

## Decisiones del usuario

1. **Visibilidad:** siempre visible en Configuración › Ventas, **independiente** del toggle
   "Modo envíos" (se expone también a tiendas de retail general).
2. **Seed:** las dos cargas iniciales van a **tiendas nuevas + todas las existentes**.

## Cambios

### 1. Frontend — tarjeta nueva con tema claro (no reutilizar la oscura)

La pantalla Ventas usa tarjetas de **tema claro** (Métodos de Pago, Vendedores, etc.).
`TransporteCard` es oscura → mezclarla rompe la consistencia visual. Por lo tanto:

- `TransporteCard` (oscura) queda **sin cambios**, exclusiva de la página Envíos.
- Nuevo componente `TransportesList` con el mismo *chrome* claro que las tarjetas hermanas:
  - Header: "Transportes" + botón `+ Nuevo`.
  - Lista: `Nombre | Activo (toggle) | Actions (editar)`.
  - **Lógica/datos reutilizados:** mismo hook `useTransportes` + endpoints `/transportes`
    (POST crear, PUT editar nombre / toggle `isActive`).
  - Ubicación: `ventago-app/src/views/config/ventas/transportes/TransportesList.tsx`.
- `ConfigurationSalesView.tsx`: agregar `<Grid item lg={4} xs={12}><TransportesList /></Grid>`
  (junto a Recargos). Seguir el patrón de import de las hermanas.
- Manejo de errores: inline `Alert` + toast global (feedback_error_visibility).

### 2. Backend — seed para tiendas nuevas

- `storeTemplate.service.ts` → agregar `createDefaultTransportes(storeId, transaction)`,
  idempotente (`findOne` por `name`+`storeId` antes de `create`), con los dos valores.
- Llamarlo dentro de `createStoreDefaults()`.

### 3. Migración — backfill de tiendas existentes

- Nuevo archivo `api-ventago/migrations/42-04-transportes-seed-defaults.sql`.
- Idempotente: por cada `stores.id`, insertar cada nombre **solo si no existe** ya
  (`WHERE NOT EXISTS` por `store_id`+`name`). No tocar transportes ya cargados.

### 4. Secuencia de despliegue (CRÍTICO)

La tabla `transportes` **no existe en producción** (migración Phase 42 sin aplicar).
La pantalla Ventas la ven **todas** las tiendas, así que si se despliega el frontend sin
la tabla/endpoint, `GET /transportes` daría 500 a todas. Orden obligatorio:

1. Desplegar `api-ventago` (módulo transportes incluido) a producción.
2. Aplicar en producción `42-01-transportes.sql` (CREATE TABLE) + `42-04-...sql` (backfill)
   — **DDL: confirmar con el usuario antes de ejecutar** (regla CLAUDE.md).
3. Recién entonces desplegar el frontend con la nueva tarjeta.

## Testing

- Local: aplicar backfill, verificar que la tarjeta aparece en Configuración › Ventas con
  los dos valores; probar agregar / editar / toggle.
- Verificar que la página Envíos sigue gateando `TransporteCard` con "Modo envíos" (sin regresión).
- ESLint (subagent) antes de push.

## Fuera de alcance

- No se cambia cómo se consumen los transportes en despacho/envíos.
- No se quita el gate `useEnvios` de la página Envíos.
