## Deferred: ventago-app `next build` fails on `src/@fake-db/mock.ts` pre-existing axios duplicate-types error

- Root cause: npm workspaces hoisted `axios` duplicated at root + local → `axios-mock-adapter`'s `AxiosStatic` vs `AxiosInstance` mismatch.
- First seen: before Wave 5 work began (commit `3e729de cambios` last touched `mock.ts`).
- NOT caused by Wave 5 changes. `next lint` passes on all Wave 5 files.
- Phase 16 Wave 5 completes anyway — runtime + ESLint + targeted file TSC pass.
- Recommended fix (separate task): add `axios` to `resolutions` in root `package.json` or delete stale duplicate `node_modules/axios`.
# Deferred Items — Phase 16 Wave 8

## Pre-existing build blocker (NOT Wave 8 scope)

**File:** `ventago-app/src/@fake-db/mock.ts:4:30`
**Error:** `TS2345: Argument of type 'AxiosStatic' is not assignable to parameter of type 'AxiosInstance'`
**Root cause:** `npm workspaces` hoists `axios` to root `node_modules/`, but `axios-mock-adapter` resolves its own copy from `ventago-app/node_modules/`, so TypeScript sees two `AxiosStatic` types and fails.
**Verified pre-existing:** `git stash && npm run build` reproduces same error at HEAD prior to Wave 8 commits.
**Wave 8 impact:** None — Wave 8 files pass `tsc --noEmit` scoped to `src/views/talleres/overview/**` and `src/hooks/api/useTalleresDashboardV2.ts` with 0 errors. ESLint passes 0 warnings on all 16 new/modified Wave 8 files.
**Resolution path:** Add `--legacy-peer-deps` or pin `axios` version in `ventago-app/package.json` workspace override. Not Wave 8 scope.
