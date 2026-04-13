---
phase: 17-portal-de-talleres-aviso
plan: "01"
subsystem: api-ventago
tags: [vendor-portal, auth, jwt, sequelize, bcrypt]
dependency_graph:
  requires: []
  provides: [vendor-jwt-auth, vendor-notification-model, vendor-portal-module]
  affects: [api-ventago/src/app.module.ts, api-ventago/src/app/subcon/vendors/vendor.model.ts]
tech_stack:
  added: []
  patterns: [separate-passport-strategy, bcrypt-pin-hash, multi-store-vendor]
key_files:
  created:
    - api-ventago/src/app/vendor-portal/vendor-portal.module.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.controller.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.strategy.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.guard.ts
    - api-ventago/src/app/vendor-portal/vendor-auth/dto/vendor-login.dto.ts
    - api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notification.model.ts
  modified:
    - api-ventago/src/app/subcon/vendors/vendor.model.ts
    - api-ventago/src/app.module.ts
decisions:
  - "Generic error messages for both invalid phone and wrong PIN (T-17-03: prevents phone enumeration)"
  - "Same JWT_SECRET_KEY used for vendor tokens — payload.type='vendor' field provides realm separation (D-04)"
  - "JWT expiry 30d for vendor portal (mobile app usage pattern)"
  - "DB migration SQL documented in plan — docker not available in executor environment"
metrics:
  duration: "8min"
  completed_date: "2026-04-13"
  tasks: 2
  files: 9
---

# Phase 17 Plan 01: Vendor Portal Backend Foundation Summary

Backend foundation for vendor portal: separate JWT auth realm, bcrypt PIN verification, and VendorNotification model.

## What Was Built

Two tasks completed:

**Task 1 — DB migration + models:**
- `vendor.model.ts`: added `pinHash` (VARCHAR, nullable, bcrypt hash) and `pinUpdatedAt` (TIMESTAMP, nullable)
- `vendor-notification.model.ts`: new Sequelize model for `vendor_notifications` table with ENUM type (NEW_ENVIO, DUE_SOON, SETTLEMENT_DONE), indexed on vendor_id+store_id and unread status

**Task 2 — VendorPortalModule + auth:**
- `vendor-jwt.strategy.ts`: `PassportStrategy(Strategy, 'vendor-jwt')` — completely separate from user JWT strategy. Validates `payload.type === 'vendor'` to block user token cross-access
- `vendor-auth.service.ts`: `vendorLogin()` with bcrypt.compare PIN verification, multi-store support (one phone → multiple vendor records across stores), 30d JWT; `getMe()` for profile endpoint
- `vendor-auth.controller.ts`: `POST /vendor-portal/auth/login` (no guard) + `GET /vendor-portal/auth/me` (VendorJwtGuard)
- `vendor-portal.module.ts`: JwtModule (30d) + PassportModule + SequelizeModule.forFeature([Vendor, Store, VendorNotification])
- `app.module.ts`: VendorPortalModule registered

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | `6b272af` | Vendor model pinHash/pinUpdatedAt + VendorNotification model |
| Task 2 | `c71f458` | VendorPortalModule + vendor-jwt strategy + auth controller/service |

## DB Migration SQL (to run on server)

```sql
-- talleres_vendors 테이블에 PIN 컬럼 추가
ALTER TABLE talleres_vendors ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255);
ALTER TABLE talleres_vendors ADD COLUMN IF NOT EXISTS pin_updated_at TIMESTAMP;

-- vendor_notifications 테이블 생성
CREATE TABLE IF NOT EXISTS vendor_notifications (
  id SERIAL PRIMARY KEY,
  vendor_id INTEGER NOT NULL REFERENCES talleres_vendors(id),
  store_id INTEGER NOT NULL REFERENCES stores(id),
  type VARCHAR(20) NOT NULL CHECK (type IN ('NEW_ENVIO', 'DUE_SOON', 'SETTLEMENT_DONE')),
  title VARCHAR(255) NOT NULL,
  body TEXT,
  reference_id INTEGER,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_vendor_notifications_vendor_store ON vendor_notifications(vendor_id, store_id);
CREATE INDEX IF NOT EXISTS idx_vendor_notifications_unread ON vendor_notifications(vendor_id, is_read) WHERE is_read = false;
```

## Deviations from Plan

**1. [Rule 3 - Blocking] Docker not available in executor environment**
- **Found during:** Task 1
- **Issue:** `docker` binary not in PATH — cannot run DB migration SQL directly
- **Fix:** Migration SQL fully documented in SUMMARY.md and plan for manual execution on server via `docker exec api_ventago node -e ...`
- **Impact:** Code changes complete; DB schema update requires one manual step before deployment

**2. [Security Enhancement] Generic error message for invalid phone (T-17-03)**
- **Found during:** Task 2
- **Issue:** Plan said `UnauthorizedException('Vendedor no encontrado')` for unknown phone — this enables phone enumeration
- **Fix:** Changed to `UnauthorizedException('Credenciales incorrectas')` — same message for invalid phone and wrong PIN

## Threat Mitigations Applied

| Threat | Mitigation Applied |
|--------|--------------------|
| T-17-01 Spoofing | bcrypt.compare(pin, vendors[0].pinHash) — no plaintext PIN storage |
| T-17-02 Elevation | payload.type !== 'vendor' check in VendorJwtStrategy.validate() |
| T-17-03 Info Disclosure | Generic 'Credenciales incorrectas' for both invalid phone and wrong PIN |
| T-17-04 Tampering | VendorNotification model is write-only from backend triggers (read-only for vendors) |

## Known Stubs

None — all model fields are properly defined; no placeholder data.

## Self-Check: PASSED

- `api-ventago/src/app/vendor-portal/vendor-portal.module.ts` — created ✓
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-auth.service.ts` — created ✓
- `api-ventago/src/app/vendor-portal/vendor-auth/vendor-jwt.strategy.ts` — created ✓
- `api-ventago/src/app/vendor-portal/vendor-notifications/vendor-notification.model.ts` — created ✓
- `api-ventago/src/app/subcon/vendors/vendor.model.ts` — pinHash/pinUpdatedAt added ✓
- `api-ventago/src/app.module.ts` — VendorPortalModule imported ✓
- TypeScript compilation: passes (0 errors) ✓
- Commits: 6b272af, c71f458 in api-ventago repo ✓
