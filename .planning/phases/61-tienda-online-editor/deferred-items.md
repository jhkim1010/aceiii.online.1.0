# Phase 61 — Deferred Items (out of plan scope)

## 61-01

- `api-ventago/src/app/shop-public/store-slug.service.ts:11` — pre-existing prettier
  formatting error (import wrap), unrelated to this plan's file set. Discovered while
  running `npx eslint src/app/shop-public/` (directory-wide) during 61-01 verification.
  Not fixed (SCOPE BOUNDARY — file not in `files_modified` for this plan).

## 61-02

- Same `store-slug.service.ts:11` pre-existing prettier error re-confirmed during
  Task 2 verification (`npx eslint src/app/shop-public/` directory-wide run). Still
  unrelated to this plan's `files_modified` (`store-theme-asset.controller.ts`,
  `shop-public.module.ts`) — both pass individually with exit 0. Not fixed.
