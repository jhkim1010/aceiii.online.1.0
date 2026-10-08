---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 08
subsystem: auth
tags: [nestjs, agent-scope, ver_admin, sucursales, impresoras, configuracion]
requires: [101-01, 101-03, 101-04]
provides:
  - "16 handlers GET marcados (6 con @AgentScopeVer, 10 con ver_admin) en 8 controladores"
  - "MANIFIESTO_ADMIN_CONFIG + EXCLUIDOS_ADMIN_CONFIG_EXTRA"
  - "agent-readonly-scopes.admin-config.spec.ts (26 tests)"
  - "tabla pestana de Configuracion -> GETs -> incluida/excluida (insumo de 101-18 Task 2)"
affects: [101-18]
key-files:
  created:
    - api-ventago/src/app/auth/guards/agent-scope-manifest.admin-config.ts
    - api-ventago/src/app/auth/guards/agent-readonly-scopes.admin-config.spec.ts
  modified:
    - api-ventago/src/app/branch/branch.controller.ts
    - api-ventago/src/app/print/print.controller.ts
    - api-ventago/src/app/store/store.controller.ts
    - api-ventago/src/app/store/config/storeConfig.controller.ts
    - api-ventago/src/app/config/configuration.controller.ts
    - api-ventago/src/app/store/whatsapp-config/store-whatsapp-config.controller.ts
    - api-ventago/src/app/integrations/wp/wp-channel.controller.ts
    - api-ventago/src/app/mercadopago/mercadopago.controller.ts
key-decisions:
  - "Los tres handlers que tomaban un storeId de la URL/query sin comprobarlo (branch store/:storeId, branch price-types-disabled, configuration by-key) ahora responden 403 a una tienda ajena (superadmin conserva el cruce); recien entonces se marcaron."
  - "Impresoras: ninguna de las 4 lecturas serializa BranchAgent; todas usan SQL con columnas explicitas o el map con maskApiKey. No hizo falta tocar print.service.ts."
requirements-completed: [D-03, D-04, D-06, D-07, D-10]
completed: 2026-10-08
---

# Phase 101 Plan 08: ver_* en sucursales, impresoras, tienda y configuracion Summary

Sucursales (lista y detalle), impresoras (overview, agentes enmascarados, impresoras por terminal, agentes termicos), tienda, configuracion, WhatsApp, canales WP y cuentas MP responden al grant con `ver_admin` (o a cualquier `ver_*` en los comunes del shell), con spec que fija la ausencia de secretos y el aislamiento de tienda.

## Commits (repo api-ventago, sin push)
- 5c450f0c: decoradores en los 8 controladores + comprobacion de tienda en 3 handlers
- 48441318: manifiesto + spec (+ tipo estructural del usuario en `by-key` por eslint)

## Handlers marcados
- `@AgentScopeVer` (4 ver_*): `BranchController.findAllByStorePaginated`, `findByStore`; `StoreController.getStoreById`; `StoreConfigController.getConfig`; `ConfigurationController.findByKey`, `findByStore`.
- `ver_admin`: `BranchController.getDetails`, `getPriceTypesDisabled`; `PrintController.overview`, `listAgents`, `terminalPrinters`, `storeThermalAgents`; `StoreWhatsappConfigController.get`; `WpChannelController.listByStore`, `getByBranch`; `MercadopagoController.listAccounts`.

## Secretos (D-10)
- Impresoras: `overview`, `terminal/:terminalId/printers` y `thermal-agents` usan SQL con columnas explicitas (sin `api_key`); `agents/:branchId` expone `apiKeyPrefix`/`hasKey` via `maskApiKey`. El servicio real (`PrintService`) se alimenta con filas que SI traen `api_key`/`apiKey`; `camposSecretosEn` de cada respuesta = [] y el valor no aparece. Ademas el SQL capturado no puede contener `api_key`, `a.*` ni `* FROM`.
- Branch `apiKey`, StoreConfig `emailApiKeyEnc`, WhatsApp `accessToken`: redactados por `toJSON` (101-04). WP: `sanitize` (sin `secret`/`wcConsumerSecret`). MP accounts: whitelist de `attributes` + `toResponse`. Store: `dniFrontKey`/`dniBackKey` ya se borran para no-superadmin.
- Control por mutacion (ambas restauradas): (1) `apiKeyPrefix: maskApiKey(a.apiKey)` -> `apiKey: a.apiKey` en `listAgents`: spec exit 1; (2) agregar `a.api_key` al SELECT de `listStoreThermalAgents`: spec exit 1.
- Observacion (no se actuo, fuera de alcance): `stores.afip_constancia_key` y `domicilio_cert_key` (rutas de objeto en MinIO de documentos fiscales) salen en `GET /store/:id` para cualquier usuario de la tienda, igual que antes; no estan en CAMPOS_SECRETOS ni se redactan para el agente.

## Aislamiento (D-03)
El tenant hook ya estrecha las lecturas, pero se hizo explicito: `branch/store/:storeId`, `branch/price-types-disabled` y `configuration/by-key` rechazan con 403 un storeId distinto del de quien llama (el agente con acceso ES la tienda del grant); superadmin conserva el cruce. `store/:id`, `store-config/:storeId` y `store-whatsapp-config/:storeId` ya tenian ese guard; `wp-channels` usa `user.storeId`. Todo en spec.

## Excluidos (D-10)
`PrintController.copyApiKey` (POST, nunca), `StoreController.feDocuments`/`feDocumentFile` (S14), `getStoreWithUsers` (101-09), `getStoreApps`, `getAvailableAppsByStore`, `fixedCustomerDni`, `backupStore`, `StoreWhatsappConfigController.ready`, `ConfigurationController.getAll`/`getById`, `BranchController.getAll`/`getById` (heredados) y `vistaPreviaSinVariantes` (EXCLUIDOS_VER). No se marcaron: mercadopago `oauth/start`, wallets/movements/refunds/payment-intents, integrations commerce/tiendanube, carpetas-compartidas, audit-log (ya en EXCLUIDOS_VER).

## Tabla de pestanas de Configuracion (insumo de 101-18 Task 2)

GETs medidos en `ventago-app/src` (grep de `apiConnector.get`/`useSWR`). "Incluida" = todos sus GETs cubiertos por algun ver_*.

| Pestana | GETs | Estado |
|---|---|---|
| Datos de la tienda | `/store/:id` | Incluida |
| Preferencias | store-config (contexto) | Incluida (sus GETs: `store-config/:storeId`) |
| Facturacion | `/afip/cert`, `/afip/cert/csr`, `/afip/issuers`, `/afip/padron/estado`, `/store/:id/fe-documents[/kind]`, `/branch/store/:id` | Excluida (cert/fe-documents: S8/S14) |
| Integraciones | `/integrations/commerce/config`, `/integrations/tiendanube/channels`, `/integrations/wp/channels`, `/whatsapp/store-config` | Excluida (commerce/tiendanube S12); `wp/channels` y whatsapp-config quedan marcados para uso suelto |
| Permisos | (101-09) | Fuera de este plan |
| Referidos | `/onboarding/referral/mine` | Excluida (no marcado) |
| Ventas | `/branch`, `/discounts/all`, `/expenses/categories/all` y `/by-store`, `/expenses/subcategories/all`, `/payment-methods/all`, `/recharges/all`, `/sellers`, `/sellers/devices` | Excluida (`sellers/devices` S3; los demas segun 101-05..07) |
| Productos | `/categories`, `/colors`, `/configuration/by-store`, `/origins`, `/price-types/all`, `/seasons`, `/sizes`, `/subcategories`, `/suppliers`, `/store-config/:id` | Depende de 101-05/06 (comunes de catalogo); este plan cubre `configuration/by-store` y `store-config` |
| Envios / Inventario / QR | `store-config/:storeId` (contexto) | Incluida (este plan) |
| Prueba virtual (IA) | `/vto/usage` | Excluida (no marcado) |
| Tienda online | `/store/:id` | Incluida (store), diseno propio no verificado |
| Campanas | WABA / clientes | Excluida (PII) |
| Token de soporte / Acceso de Ventago | acceso | Excluida (S16) |
| Relojes | dispositivos | Excluida (S14) |
| Importar legacy | legacy | Excluida |
| MercadoPago (pagina `/configuracion/mercadopago`) | `/mercadopago/accounts` | Incluida (solo accounts) |
| WhatsApp (pagina `/configuracion/whatsapp`) | `/store-whatsapp-config/:id` | Incluida |

## Deviations from Plan
- [Rule 2] Se agrego comprobacion de tienda (403) en `branch store/:storeId`, `price-types-disabled` y `configuration by-key` (la nota del orquestador pide no marcar handlers con :storeId sin comprobar). Cambia el comportamiento solo para quien pedia otra tienda (antes recibia lista vacia por el hook).
- [Rule 3] Ambos commits con jest manual: el gate del primer commit aborto (crash V8 con 6 directorios juntos) y el del segundo supero 180s (open handle preexistente). Commit 1 y 2 con `SKIP_VERIFY=1` (motivo en el mensaje); jest manual por modulo `--maxWorkers=1 --forceExit` exit 0 en `src/app/auth/guards`, `src/app/print`, `src/app/branch`, `src/app/store`, `src/app/mercadopago`, `src/app/integrations/wp`; `src/app/config` no tiene specs. tsc exit 0.
- print.service.ts no se toco (no hizo falta).

## Known Stubs
None.

## Self-Check: PASSED
5c450f0c y 48441318 existen en api-ventago; manifiesto y spec existen.
