# Phase 42 — Deferred Items (out-of-scope discoveries)

Logged during execution. NOT fixed — outside the touched task's scope (executor scope-boundary rule).

| # | Discovered in | Item | Reason deferred |
|---|---------------|------|-----------------|
| 1 | 42-02 Task 4 (tsc full check) | `src/app/mercadopago/webhook/mp-webhook.service.spec.ts:72,178` — `error TS2554: Expected 9 arguments, but got 7` (MpWebhookService constructor signature drift vs spec) | Pre-existing (Phase 29 area), unrelated to online-orders. Not introduced by Phase 42. Backend is SWC at runtime so this is a test-compile issue only, not a boot/build gate. Should be addressed by whoever owns mp-webhook tests. |
