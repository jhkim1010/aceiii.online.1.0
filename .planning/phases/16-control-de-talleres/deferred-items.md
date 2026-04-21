## Deferred: ventago-app `next build` fails on `src/@fake-db/mock.ts` pre-existing axios duplicate-types error

- Root cause: npm workspaces hoisted `axios` duplicated at root + local → `axios-mock-adapter`'s `AxiosStatic` vs `AxiosInstance` mismatch.
- First seen: before Wave 5 work began (commit `3e729de cambios` last touched `mock.ts`).
- NOT caused by Wave 5 changes. `next lint` passes on all Wave 5 files.
- Phase 16 Wave 5 completes anyway — runtime + ESLint + targeted file TSC pass.
- Recommended fix (separate task): add `axios` to `resolutions` in root `package.json` or delete stale duplicate `node_modules/axios`.
