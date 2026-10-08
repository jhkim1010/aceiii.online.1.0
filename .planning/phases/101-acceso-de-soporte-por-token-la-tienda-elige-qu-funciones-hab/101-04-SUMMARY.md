---
phase: 101-acceso-de-soporte-por-token-la-tienda-elige-qu-funciones-hab
plan: 04
subsystem: api-ventago / secretos en respuestas
tags: [security, serialization, toJSON, D-07, D-10]
requires: []
provides:
  - CAMPOS_SECRETOS / camposSecretosEn (catalogo + detector para 101-05..09)
  - instanciaOffline (helper de specs de redaccion sin Sequelize inicializado)
  - OnlineOrder.toJSON sin confirmToken / confirmTokenExpiresAt
  - Branch.toJSON sin apiKey
affects: [online-orders, branch]
key-files:
  created:
    - api-ventago/src/common/secretos/campos-secretos.ts
    - api-ventago/src/common/secretos/instancia-offline.ts
    - api-ventago/src/common/secretos/respuesta-sin-secretos.spec.ts
    - api-ventago/src/app/online-orders/online-order-secretos.spec.ts
    - api-ventago/src/app/branch/branch-secretos.spec.ts
  modified:
    - api-ventago/src/app/online-orders/online-order.model.ts
    - api-ventago/src/app/branch/branch.model.ts
key-decisions:
  - "Specs de modelos con muchas asociaciones usan instanciaOffline (Object.create del prototipo + get/getDataValue) en vez de new Sequelize({models}), que falla con 'Store has not been defined'."
metrics:
  tasks: 2
  completed: 2026-10-08
---

# Phase 101 Plan 04: Secretos fuera del JSON Summary

OnlineOrder y Branch dejan de serializar `confirmToken`/`confirmTokenExpiresAt`/`apiKey` (con `confirmTokenSet` / `hasApiKey` como indicadores), y queda un catalogo unico de campos secretos con detector exacto mas specs que fijan las redacciones ya existentes.

## Commits (repo api-ventago, sin push)
- 4901f38f feat(101-04): catalogo de campos secretos + detector
- aa1ed351 feat(101-04): redactar confirmToken y Branch.apiKey del JSON + fijar redacciones existentes

## Re-medicion del catalogo (DB local 5432, public + reseller)
Columnas que coinciden con el patron: Sellers.pin_hash, active_sessions.session_token, admin_device_tokens.(prev_token_hash|token_hash), branch_agents.api_key, branch_printer_configs.api_key, branches.api_key, commerce_channels.(secret|wc_consumer_secret), despacho_devices.api_key, despacho_operarios.pin_hash, legacy_import_runs.lease_token, legacy_upload_sessions.lease_token, mobile_sessions.(active_session_token|fcm_token), mp_accounts.(access_token|refresh_token), notas.secret_hash, online_orders.(confirm_token|confirm_token_expires_at), pending_registrations.(password_hash|token), revendedores.password, store_configs.email_api_key_enc, store_whatsapp_config.access_token, subscription_config.(mp_access_token|stripe_secret_key), support_tokens.(token|token_hash), talleres_vendors.pin_hash, terminal_devices.device_token, users.password, vendedor_devices.api_key, verification_codes.code_hash, watch_devices.token_hash, watch_pairing_codes.(device_code_hash|user_code_hash), wp_channels.(secret|secret_prev|wc_consumer_secret), reseller.resellers.password.

Reconciliacion con la lista del plan:
- Nuevas en DB y agregadas al catalogo: admin_device_tokens.(token_hash|prev_token_hash), legacy_*.lease_token, verification_codes.code_hash, watch_pairing_codes.*_code_hash, reseller.resellers.password (cubierto por `password`).
- Descartadas (no son secretos): notas.is_secret (flag), users.must_change_password (flag), sale_idempotency_keys.request_hash, wp_order_states.payload_hash, store_themes.*_tokens (design tokens), support_access_grants.token_id (FK), wp_channels.secret_prev_hasta (fecha).
- `support_access_grants.key` del plan NO existe en la DB local (aun no lo crea ninguna migracion aplicada); el catalogo incluye `token` generico que cubre support_tokens.token.
- `users.mobile_pin` no aparece en el patron de la consulta pero se mantiene en el catalogo (redaccion existente de Users, ver models).

## Deviations from Plan
- [Rule 3 - Blocking] `Model.build` con `new Sequelize({models})` no es viable offline para Branch/OnlineOrder/StoreConfig (asociaciones a Store, etc.: "Store has not been defined"). Se agrego `src/common/secretos/instancia-offline.ts` y los specs llaman el `toJSON` real sobre esa instancia. El getter interno de OnlineOrder no se prueba como getter de Sequelize (el codigo de `ensureConfirmToken` no cambio y su suite sigue verde).
- Users (defaultScope) y wp `sanitize` (privado): no se agrego spec nuevo. Users ya redacta por defaultScope y requiere DB para probar el scope; `sanitize` es metodo privado de servicio con DI. Quedan sin fijar por spec en este plan (a retomar si 101-05+ lo necesita). `maskApiKey` de print si esta fijado.
- Control "sin override" en OnlineOrder se hace con `Model.prototype.toJSON.call(...)`; en Branch/StoreConfig/WhatsApp con datos crudos.

## Verificacion
- jest `src/app/online-orders` (exit 0), `src/app/branch` + `src/common/secretos` (exit 0), tsc --noEmit exit 0, eslint limpio en los archivos tocados.
- Mutaciones: comentar `delete values.confirmToken` -> online-order-secretos.spec exit 1; comentar `delete values.apiKey` -> branch-secretos.spec exit 1; ambas restauradas.
- Consumidores: `products.service.ts:1220` lee `branch.apiKey` por propiedad (no por JSON) -> intacto. ModalBranch.tsx solo envia apiKey, no lo lee. Nadie en ventago-app/Flutter lee `confirmToken`.

## Known Stubs
None.

## Self-Check: PASSED
