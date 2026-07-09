# Modo Revendedor — BLOCKED (Phase 24 gate, D-07)

> ⛔ **Esta feature NO se envía todavía.** Es un esqueleto explícitamente bloqueado.
> 이 폴더는 의도적으로 **차단된 스켈레톤**이다. Phase 24 스키마가 도착하기 전엔 실제
> 로직을 구현하지 않는다 (D-07). 현재는 두 화면이 "Próximamente — requiere Phase 24"
> placeholder 만 렌더한다.

---

## 1. Dependencia externa que falta (Phase 24 Wave 1-2)

El modo revendedor depende de dos artefactos de esquema que **NO existen aún** en la base
de datos (verificado ausente en `.planning/intel/db-schema-tables.md`):

| Artefacto | Tipo | Rol |
|-----------|------|-----|
| `reseller.catalog_unified` | **materialized view** | catálogo unificado (N tiendas) que el revendedor puede vender |
| `reseller_tienda_link` | **tabla** (`store_id`, `reseller_id`) | qué tiendas puede ver/vender cada revendedor → alimenta `MultiStoreScope` |

Mientras estos dos artefactos no estén creados y aplicados (local PG18 + operación PG10),
**no se construye nada de revendedor**. Construir contra un contrato inexistente = ruptura
silenciosa (threat T-37-21).

## 2. ⚠️ NO confundir con el módulo legacy `revendedores`

Existe un módulo backend `api-ventago/src/app/revendedor/` con la tabla `revendedores`.
**Es un concepto DISTINTO y no relacionado** con el esquema `reseller.*` de Phase 24.

- Legacy `revendedores` → portal de reventa antiguo (otro dominio).
- Phase 24 `reseller.catalog_unified` + `reseller_tienda_link` → catálogo multi-tienda para
  el modo revendedor de la app móvil.

No reutilizar ni mapear el módulo legacy para implementar este modo.

## 3. Checklist de activación (cuando Phase 24 Wave 1-2 esté confirmado)

Ejecutar en un plan futuro **solo después** de confirmar que `reseller.catalog_unified` y
`reseller_tienda_link` existen y están aplicados:

- [ ] **Backend — `MobileAuthService` revendedor scope**: resolver `scopeStoreIds` desde
      `reseller_tienda_link` (store_id IN links del reseller). Hoy la rama revendedor de
      `MobileAuthService` está sin llenar. **No tocar en este plan.**
- [ ] **Backend — `MobileScopeGuard` rama revendedor** (threat T-37-20, EoP): forzar
      `store_id IN (SELECT store_id FROM reseller_tienda_link WHERE reseller_id = :me)`.
      El cliente es solo display/lock; el guard es la autoridad (D-02).
- [ ] **Backend — `/mobile/catalog` + `/mobile/stock/:id` rama revendedor**: hoy ambas lanzan
      `NOT_IMPLEMENTED` para revendedor. Conectar contra `reseller.catalog_unified`.
- [ ] **Frontend — Store selector**: reemplazar el stub por el selector real de las N tiendas
      permitidas (`MultiStoreScope.storeIds`). Reutilizar `store_tab_bar.dart` cuando exista
      (patrón clonado de talleres-vendor-app) y `MultiStoreScope` de `scope_provider.dart`.
- [ ] **Frontend — Catálogo búsqueda-a-lista (D-14)**: entrada por **búsqueda/lista, NO QR**
      (a diferencia de vendedor, que es QR-first). El QR de percha es por-sucursal; el
      revendedor opera cross-tienda, así que navega por búsqueda.
- [ ] **Frontend — Cotización / pedido = pendiente / 보류 (D-13, Caja-neutral)**: crear
      cotizaciones/pedidos que se comportan como **suspendido/pendiente**, sin UI de pago y
      **sin afectar Caja ni saldo** (igual que vendedor "Mandar a Caja"). Reemplazar el stub
      `quote_screen.dart`.
- [ ] **Tests**: scope resolution (`MultiStoreScope`), guard cross-store denial (403
      `SCOPE_VIOLATION`), cotización pendiente = Caja-neutral.

## 4. Contrato de activación (interfaces a reutilizar)

Ya existen y compilan hoy; **no se modifican en este plan bloqueado**:

- `lib/features/auth/providers/scope_provider.dart` → `MultiStoreScope(storeIds, user)` ya
  modela el scope multi-tienda (resuelto desde `/mobile/me` cuando `scopeMode == revendedor`).
- `lib/router/app_router.dart` → rama de ruta `MultiStoreScope` lleva a `/revendedor/stores`
  (este esqueleto), dejando la navegación vendedor intacta.

## 5. Archivos de este esqueleto (solo placeholders)

- `README.md` — este bloque de dependencia + checklist de activación.
- `views/store_selector_screen.dart` — placeholder "Próximamente — requiere Phase 24".
- `views/quote_screen.dart` — placeholder "Próximamente — requiere Phase 24".

Ninguno hace llamadas a API ni contiene lógica de catálogo/stock/cotización.
