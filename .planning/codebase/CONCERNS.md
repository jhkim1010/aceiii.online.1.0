# Codebase Concerns

**Analysis Date:** 2026-04-01

## Tech Debt

**Sale creation has no database transaction:**
- Issue: `SalesCreateService.create()` performs sale creation, stock movements, payment method records, discounts, and recharges as individual sequential DB operations without wrapping in a transaction. If any step fails mid-way, the database is left in an inconsistent state (e.g., sale created but stock not deducted, or stock deducted but payment not recorded).
- Files: `api-ventago/src/app/sales/sales-create.service.ts` (lines 42-141)
- Impact: **Critical** - Data integrity risk for the core business operation (POS sales). A network hiccup or DB error during stock creation leaves orphaned sales or phantom inventory.
- Fix approach: Wrap the entire `create()` method in `this.sequelize.transaction()` and pass the transaction to each `.create()` call. The `nullifySale()` method in the same file also lacks a transaction.

**CrudController endpoints lack auth guards:**
- Issue: Many controllers extend `CrudController` without applying `@Auth()` or `@UseGuards()`. The `CrudController` base class has no guards — it only does a soft `if (!user) return []` check. This means unauthenticated requests hit the database (returning empty results) instead of being rejected at the guard level.
- Files:
  - `api-ventago/src/common/crud/crud.controller.ts` (base class, no guards)
  - `api-ventago/src/app/stocks/stocks.controller.ts` (no auth on any endpoint)
  - `api-ventago/src/app/modules/modules.controller.ts` (no auth)
  - `api-ventago/src/app/apps/apps.controller.ts` (no auth)
  - `api-ventago/src/app/functions/functions.controller.ts` (no auth)
- Impact: **High** - Stock movements, module listings, and app configurations are accessible without authentication. The stocks controller allows unauthenticated POST/PUT/DELETE which can modify inventory data.
- Fix approach: Either add a global `APP_GUARD` for JWT auth with a `@Public()` decorator for intentionally public endpoints, or add `@Auth()` to all controllers that extend `CrudController`.

**Hardcoded API key in frontend:**
- Issue: The axios instance sends `'x-api-key': '12345'` as a static header on every request. This is not a real security mechanism.
- Files: `ventago-app/src/services/api.service.ts` (line 17)
- Impact: **Low** - Not a real vulnerability since JWT auth is the actual gate, but it creates a false sense of security and should either be removed or replaced with a proper mechanism.
- Fix approach: Remove the hardcoded header or replace with a proper API key from environment config.

**JWT secret fallback is `'ventago'`:**
- Issue: If `JWT_SECRET_KEY` env var is not set, the JWT secret defaults to the string `'ventago'`. This is extremely weak and predictable.
- Files: `api-ventago/src/config/env.config.ts` (line 16), `api-ventago/src/app/auth/auth.module.ts` (line 31)
- Impact: **Critical in production if env var missing** - Anyone can forge valid JWT tokens. The fallback should throw an error instead of using a default.
- Fix approach: Remove the fallback and throw a startup error if `JWT_SECRET_KEY` is not configured.

**Excessive `console.log` usage (131 occurrences in backend, 95 in frontend):**
- Issue: Both backend and frontend have extensive `console.log` statements. The backend has Winston logger configured but many services still use `console.log` directly, bypassing structured logging.
- Files: 17 backend files, 30 frontend files (see `api-ventago/src/app/store/storeTemplate.service.ts`, `api-ventago/src/app/auth/auth.service.ts`, `api-ventago/src/database/sync.service.ts`, etc.)
- Impact: **Medium** - Unstructured logs in production, potential sensitive data leakage via console output, harder to monitor and debug.
- Fix approach: Replace `console.log` with `this.logger.log()` (Winston) in backend. Add a lint rule to disallow `console.log`.

**`any` type used extensively (107+ occurrences in backend):**
- Issue: Heavy use of `any` type throughout the backend codebase weakens TypeScript's type safety. The `CrudService.create()` accepts `data: any`, `CrudController.create()` accepts `@Body() body: any`, and many internal variables use `any`.
- Files: `api-ventago/src/common/crud/crud.service.ts`, `api-ventago/src/common/crud/crud.controller.ts`, `api-ventago/src/app/store/store.service.ts` (line 40), and 100+ other locations
- Impact: **Medium** - Runtime type errors that TypeScript should catch at compile time, harder refactoring, reduced IDE assistance.
- Fix approach: Replace `any` with proper DTOs and generics in the CRUD base classes. Start with the most critical paths (sales, auth, store).

## Security Considerations

**SQL injection via `literal()` with string interpolation:**
- Risk: Multiple services build SQL fragments by interpolating user-controlled values directly into `Sequelize.literal()` strings. The `tz` (timezone) comes from the database, but `startDate`/`endDate` parameters come from client requests and are interpolated directly into SQL.
- Files:
  - `api-ventago/src/app/sales/sales.service.ts` (lines 39-42) - `literal(...'${startDate}'...)`
  - `api-ventago/src/app/sales/sales-create.service.ts` (line 92) - `literal(...'${tz}'...)`
  - `api-ventago/src/app/expenses/expenses.service.ts` (lines 66-69) - `literal(...'${params.dateFrom}'...)`
- Current mitigation: ValidationPipe with `whitelist: true` is enabled globally, and DTOs use class-validator decorators. However, date string format validation may not be strict enough to prevent SQL injection.
- Recommendations: Use parameterized queries or Sequelize's built-in date operators instead of `literal()`. If `literal()` is required, sanitize/validate the date format strictly (e.g., regex match `^\d{4}-\d{2}-\d{2}$`).

**Stack traces exposed in 500 error responses:**
- Risk: The global exception filter includes the full stack trace in the HTTP response body for 500 errors (line 41: `errorResponse = { statusCode, message, error, stack }`).
- Files: `api-ventago/src/common/filters/all-exceptions.filter.ts` (line 41)
- Current mitigation: None.
- Recommendations: Remove `stack` from the response payload. Stack traces should only appear in server logs (which is already done on line 58-62), never in API responses.

**CORS is fully open:**
- Risk: Both the HTTP server (`cors: true`) and WebSocket gateway (`origin: '*'`) accept requests from any origin.
- Files: `api-ventago/src/main.ts` (lines 11, 39), `api-ventago/src/common/socket/websocket.gateway.ts` (lines 14-16)
- Current mitigation: JWT authentication on most endpoints.
- Recommendations: Restrict CORS to known domains (`ventago.coolsistema.com`, `localhost:3050` for dev).

**No rate limiting:**
- Risk: No `@nestjs/throttler` or similar rate limiting mechanism is in place. Public endpoints (marketplace purchase, public products) and the login endpoint are vulnerable to brute-force attacks.
- Files: `api-ventago/src/main.ts` (no throttler configured)
- Current mitigation: None.
- Recommendations: Install `@nestjs/throttler` and apply it globally, with stricter limits on auth and public endpoints.

**WebSocket has no authentication:**
- Risk: The WebSocket gateway accepts any connection and allows clients to register with any `apiKey` or `userId/storeId`. No token verification occurs on WebSocket connections.
- Files: `api-ventago/src/common/socket/websocket.gateway.ts` (lines 24-47)
- Current mitigation: None.
- Recommendations: Validate JWT token during WebSocket handshake in `handleConnection()` before accepting the connection.

**SessionGuard is not applied to any controller:**
- Risk: `SessionGuard` exists but `@UseGuards(SessionGuard)` is never used in any controller. The session security system (duplicate login prevention, device/IP binding) is implemented but the guard enforcement layer is not applied.
- Files: `api-ventago/src/app/session/guards/session.guard.ts` (defined but unused)
- Current mitigation: Frontend handles session expiration via response interceptor, but server-side enforcement is missing.
- Recommendations: Apply `SessionGuard` to controllers that should enforce single-session policy (sales, cash register, etc.).

## Performance Bottlenecks

**Sale creation makes N+1 queries for stock:**
- Problem: For each sale item, a separate `Stocks.create()` call is made in a sequential for-loop. A sale with 20 items makes 20 individual INSERT queries.
- Files: `api-ventago/src/app/sales/sales-create.service.ts` (lines 121-129)
- Cause: Sequential `await` in a for-loop instead of bulk operation.
- Improvement path: Use `Stocks.bulkCreate()` to insert all stock movements in a single query.

**No connection pool configuration:**
- Problem: The Sequelize database connection uses default pool settings (min: 0, max: 5). For a multi-tenant POS system with concurrent sales across multiple stores, 5 connections may be insufficient.
- Files: `api-ventago/src/database/database.module.ts` (no `pool` config in `useFactory`)
- Cause: Default Sequelize pool settings.
- Improvement path: Add explicit pool configuration: `pool: { max: 20, min: 5, acquire: 30000, idle: 10000 }`.

**Large frontend components (500-685 lines):**
- Problem: Several view components are monolithic with complex state management within a single file.
- Files:
  - `ventago-app/src/views/homes/components/InfoClient.tsx` (685 lines)
  - `ventago-app/src/views/products/list/components/BasicDataCard.tsx` (673 lines)
  - `ventago-app/src/views/products/list/ProductsView.tsx` (661 lines)
  - `ventago-app/src/views/codigo-vista/CodigoVistaView.tsx` (660 lines)
  - `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` (585 lines)
- Cause: Features accumulated in single components without decomposition.
- Improvement path: Extract sub-components, custom hooks, and helper functions. Priority: POS view (`ProductList.tsx`) since it directly impacts sales performance.

**`store.service.ts` is the largest backend file (776 lines):**
- Problem: The store service handles CRUD, backup/restore, dashboard queries, statistics, and more in a single service.
- Files: `api-ventago/src/app/store/store.service.ts` (776 lines)
- Cause: God-object pattern accumulating responsibilities.
- Improvement path: Split into `StoreService`, `StoreBackupService`, `StoreDashboardService`, etc.

## Fragile Areas

**Daily number race condition:**
- Files: `api-ventago/src/app/sales/sales-create.service.ts` (lines 88-99)
- Why fragile: The daily sale number is calculated by querying the max `dailyNumber` and adding 1. Without a transaction or database-level lock, two concurrent sales can get the same number.
- Safe modification: Use a database sequence or `SELECT ... FOR UPDATE` within a transaction.
- Test coverage: No tests exist (zero test files in the entire backend).

**Marketplace public purchase - no price validation:**
- Files: `api-ventago/src/app/marketplace/public-purchase/public-purchase.service.ts` (line 343 TODO comment)
- Why fragile: The public purchase endpoint trusts client-sent prices. A malicious client can submit any price for items. The TODO comment explicitly acknowledges this gap.
- Safe modification: Add server-side price validation comparing `ProductVisibility.marketplacePrice` with the submitted price before creating the sale.
- Test coverage: None.

## Test Coverage Gaps

**Zero test files in the entire codebase:**
- What's not tested: Everything. There are no `.spec.ts` or `.test.ts` files anywhere in `api-ventago/src/` or `ventago-app/src/`.
- Files: N/A - no test files exist
- Risk: **Critical** - Any code change can break existing functionality without detection. The sale creation flow, auth system, session management, multi-tenant data isolation, and financial calculations have zero automated verification.
- Priority: **High** - Start with:
  1. `api-ventago/src/app/sales/sales-create.service.ts` - Core revenue path
  2. `api-ventago/src/app/auth/auth.service.ts` - Authentication
  3. `api-ventago/src/common/crud/crud.service.ts` - Multi-tenant data isolation
  4. `api-ventago/src/app/session/session.service.ts` - Session security

## Missing Critical Features

**No error boundaries in React:**
- Problem: The frontend has zero `ErrorBoundary` components. Any unhandled error in a React component tree crashes the entire application.
- Blocks: Graceful degradation when a single widget fails (e.g., a dashboard chart error shouldn't crash the POS screen).
- Files: No `ErrorBoundary` usage found in `ventago-app/src/`
- Fix: Add error boundaries at page level and around critical independent components (charts, modals).

**50MB JSON body limit:**
- Problem: `main.ts` sets `express.json({ limit: '50mb' })` for backup restore, but this applies globally to all endpoints. An attacker can send 50MB payloads to any endpoint.
- Files: `api-ventago/src/main.ts` (line 37)
- Fix: Apply the 50MB limit only to the backup restore endpoint; keep the default (100KB) for all others.

## Dependencies at Risk

**Sequelize v6 with @sequelize/core v7-alpha in parallel:**
- Risk: `package.json` includes both `sequelize: ^6.37.5` and `@sequelize/core: ^7.0.0-alpha.44`. Running two major versions of the same ORM creates confusion and potential conflicts.
- Files: `api-ventago/package.json` (lines 52-53, 35)
- Impact: Bundle size bloat, potential import confusion, alpha-version instability.
- Migration plan: Complete migration to Sequelize v7 when it reaches stable, or remove the v7-alpha dependency.

**Next.js 13.3.2 (Pages Router):**
- Risk: Next.js 13.3 is outdated (current stable is 14+). The Pages Router is in maintenance mode with the App Router being the future direction.
- Files: `ventago-app/package.json` (line 57)
- Impact: Missing security patches, performance improvements, and modern features.
- Migration plan: Not urgent, but plan for incremental migration to App Router for new pages.

---

*Concerns audit: 2026-04-01*
