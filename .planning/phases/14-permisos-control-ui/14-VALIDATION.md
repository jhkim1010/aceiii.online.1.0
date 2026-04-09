---
phase: 14
slug: permisos-control-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-09
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual verification + build checks |
| **Config file** | none |
| **Quick run command** | `cd api-ventago && npm run build && cd ../ventago-app && npm run build` |
| **Full suite command** | `cd api-ventago && npm run build && cd ../ventago-app && npm run build` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run build checks
- **After every plan completes:** Full build verification

---

## Validation Architecture

Extracted from RESEARCH.md:

1. **Backend Guard validation:** Verify `@FunctionGuard(slug, action)` decorator blocks unauthorized API calls
2. **CASL ability validation:** Verify `buildAbilityFor()` builds granular abilities from `/me` permissions map
3. **Navigation hiding:** Verify `user.structure` filters menu items based on permissions
4. **DB migration safety:** Verify existing RoleFunction rows get all 4 CRUD actions by default
5. **ESLint compliance:** All new files pass `newline-before-return`, `lines-around-comment`, `no-unused-vars`
