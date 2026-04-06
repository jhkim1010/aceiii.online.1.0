# Architecture

**Analysis Date:** 2026-04-01

## Pattern Overview

**Overall:** Multi-service monorepo with NestJS API backend, Next.js Pages Router frontend, and a Node.js print agent, connected via REST API and WebSocket (Socket.io).

**Key Characteristics:**
- npm workspaces monorepo with 3 packages: `api-ventago`, `ventago-app`, `print-agent`
- Multi-tenant SaaS with `store_id` isolation across nearly all tables
- Hierarchical tenant structure: Store > Branch (Sucursal) > Box (Caja) > Terminal
- JWT + session token dual-layer authentication with device fingerprint and IP binding
- Sequelize ORM with `underscored: true` global setting (camelCase model props -> snake_case DB columns)
- CASL-based attribute ACL on frontend, role-based guards on backend

## Layers

**API Layer (Controllers):**
- Purpose: Handle HTTP requests, validate input, delegate to services
- Location: `api-ventago/src/app/*/` (each module has its own controller)
- Contains: Route handlers with decorators (`@Get`, `@Post`, `@UseGuards`)
- Depends on: Services, Guards, DTOs
- Used by: Frontend via Axios (`apiConnector`)

**Service Layer:**
- Purpose: Business logic, database operations, cross-module coordination
- Location: `api-ventago/src/app/*/*.service.ts`
- Contains: Sequelize model queries, business rules, transaction orchestration
- Depends on: Sequelize models (via `@InjectModel()`), other services
- Used by: Controllers, other services

**Model Layer (Sequelize):**
- Purpose: Database table definitions and relationships
- Location: `api-ventago/src/app/*/*.model.ts`
- Contains: `@Table`, `@Column`, `@ForeignKey`, `@BelongsTo`, `@HasMany` decorators
- Depends on: Sequelize ORM with `sequelize-typescript`
- Used by: Services via `@InjectModel()` injection
- **Critical rule:** `underscored: true` globally in `api-ventago/src/database/database.module.ts` means model `camelCase` -> DB `snake_case`

**Common/Infrastructure Layer:**
- Purpose: Cross-cutting concerns shared by all modules
- Location: `api-ventago/src/common/`
- Contains:
  - `crud/` - Base CRUD module
  - `decorators/` - Custom decorators (`@Audit`)
  - `dto/` - Shared DTOs
  - `excel/` - Excel export utilities
  - `filters/` - Exception filters (`AllExceptionsFilter` at `api-ventago/src/common/filters/all-exceptions.filter.ts`)
  - `interceptors/` - Audit interceptor (`api-ventago/src/common/interceptors/audit.interceptor.ts`)
  - `logger/` - Winston logger config
  - `middleware/` - HTTP logger middleware
  - `minio/` - MinIO file storage service (`api-ventago/src/common/minio/`)
  - `socket/` - WebSocket gateway and service (`api-ventago/src/common/socket/`)
  - `utils/` - Shared utilities

**Frontend Presentation Layer (Pages):**
- Purpose: Route-based page components (Next.js Pages Router)
- Location: `ventago-app/src/pages/`
- Contains: Thin page components that render views
- Depends on: Views, Layouts, Auth context

**Frontend View Layer:**
- Purpose: Feature-specific UI components with business logic
- Location: `ventago-app/src/views/`
- Contains: Complex view components, feature-specific hooks, sub-components
- Depends on: Services (`apiConnector`), hooks, components, context

**Frontend Shared Components:**
- Purpose: Reusable UI building blocks
- Location: `ventago-app/src/components/`
- Contains: Dialogs, forms, tables, buttons, cards, filters, modals, team-chat
- Depends on: MUI components, utility functions

**Frontend Core Framework (`@core`):**
- Purpose: Theme engine, layout system, base components (template-level code)
- Location: `ventago-app/src/@core/`
- Contains: Layout components, theme config, MUI overrides, auth guards, context providers
- **Do not modify** unless changing the core layout/theme system

## Data Flow

**Standard API Request (Frontend -> Backend -> DB):**

1. Frontend calls `apiConnector.get('/path')` or `apiConnector.post('/path', body)` from `ventago-app/src/services/api.service.ts`
2. Axios interceptor injects `Authorization: Bearer {JWT}`, `x-session-token`, and `x-branch-id` headers automatically
3. NestJS receives request, `HttpLoggerMiddleware` logs it (`api-ventago/src/common/middleware/http-logger.middleware.ts`)
4. `JwtStrategy` validates JWT token (`api-ventago/src/app/auth/strategies/jwt.strategy.ts`)
5. Optional `SessionGuard` validates session token (`api-ventago/src/app/session/guards/session.guard.ts`)
6. Optional `UserRoleGuard` checks role permissions (`api-ventago/src/app/auth/guards/user-role.guard.ts`)
7. `ValidationPipe` validates DTO (whitelist + forbidNonWhitelisted)
8. Controller delegates to Service
9. Service queries PostgreSQL via Sequelize model
10. `AuditInterceptor` logs the action if `@Audit()` decorator is present
11. Response returns through chain; `AllExceptionsFilter` catches any errors

**Authentication Flow:**

1. User submits credentials + device fingerprint to `POST /api/auth/login`
2. `AuthService` (`api-ventago/src/app/auth/auth.service.ts`) validates credentials
3. Existing `ActiveSession` for user is deleted (single-session enforcement)
4. IP checked against `BranchIpRegistry` - if unknown, returns `requireBranchRegistration: true`
5. Device fingerprint checked against `TerminalDevice` - if unknown, returns `requireTerminalRegistration: true`
6. If both pass, JWT + `sessionToken` (UUID v4) issued
7. Frontend (`ventago-app/src/context/AuthContext.tsx`) stores tokens in `localStorage`
8. On subsequent requests, `api.service.ts` interceptor auto-injects both tokens
9. Session expiry (another login) triggers `SESSION_EXPIRED` -> frontend redirects to `/login?reason=session_expired`

**Real-time Print Flow (WebSocket):**

1. Backend `WebsocketService` emits `print_invoice` event to specific apiKey room (`api-ventago/src/common/socket/websocket.service.ts`)
2. `print-agent/src/index.js` connects to `/realtime` namespace via Socket.io
3. Registers with `register_api_key` event on connect
4. Receives `print_invoice`, formats with `formatter.js`, prints via `printer.js` (ESC/POS)
5. Sends `print_confirmation` back to server

**State Management:**
- **Backend:** Stateless (JWT + session token per request). No in-memory state except WebSocket connections.
- **Frontend:**
  - `AuthContext` (`ventago-app/src/context/AuthContext.tsx`): User auth state, selected branch, login/logout
  - `SystemContext` (`ventago-app/src/context/SystemContext.tsx`): Current system/app mode ('venta' default)
  - `SettingsContext` (`ventago-app/src/@core/context/settingsContext.tsx`): Theme/layout settings
  - Redux store (`ventago-app/src/store/index.ts`): Minimal usage, only `user` slice currently
  - `localStorage`: accessToken, sessionToken, userData, selectedBranchId, role

## Multi-Tenant Architecture

**Hierarchy:** `Store → Branch (Sucursal) → Box (Caja) → Terminal`

**Data Isolation:**
- Nearly every table has `store_id` FK for tenant isolation
- `x-branch-id` header sent on every request for branch-level filtering
- Backend services filter queries by `store_id` from JWT user context

**Global vs Store Data Pattern (SharedModule):**
- `api-ventago/src/app/shared/` implements dual-layer data model
- **Global data** (all stores share): `GlobalClient`, `GlobalCategory`, `GlobalSubcategory`
- **Store data** (per-store private): `StoreClient`, `StoreCategory`, `StoreSubcategory`
- Example: Customer name is global, but credit balance is store-specific

**Store Initialization:**
- `StoreTemplateService` (`api-ventago/src/app/store/storeTemplate.service.ts`): Creates default Branch + Box + Terminal on new store
- `BranchService` (`api-ventago/src/app/branch/branch.service.ts`): Creates default Box + Terminal on new branch

## Key Abstractions

**NestJS Module Pattern:**
- Purpose: Each business domain is a self-contained NestJS module
- Examples: `api-ventago/src/app/sales/sales.module.ts`, `api-ventago/src/app/products/products.module.ts`
- Pattern: Module imports `SequelizeModule.forFeature([Models])`, declares Controller + Service, exports Service for cross-module use

**MinIO File Storage:**
- Purpose: S3-compatible object storage for logos, images
- Location: `api-ventago/src/common/minio/`
- Pattern: Import `MinioModule`, inject `MinioService`, call `uploadFile(file, fileName)` -> returns `{ fileName }`
- Frontend URL: `{API_HOST}/minio/{fileName}`

**Audit Logging:**
- Purpose: Track entity changes with user/IP attribution
- Location: `api-ventago/src/common/decorators/audit.decorator.ts`, `api-ventago/src/common/interceptors/audit.interceptor.ts`
- Pattern: Add `@Audit({ entityType: 'sale', action: 'create' })` decorator to controller method

**Dynamic Navigation:**
- Purpose: Sidebar menu built from user's `structure` (apps/modules assigned to their store)
- Location: `ventago-app/src/navigation/vertical/index.ts`
- Pattern: `user.structure` array contains apps with modules; `useNavigation()` hook transforms to nav items

## Entry Points

**Backend Entry:**
- Location: `api-ventago/src/main.ts`
- Triggers: `npm run dev:api` or Docker container start
- Responsibilities: Create NestJS app, apply global prefix `/api`, register global pipes/filters/interceptors, listen on port 5002

**Frontend Entry:**
- Location: `ventago-app/src/pages/_app.tsx`
- Triggers: Next.js page load
- Responsibilities: Provider stack (PostHog > Redux > Emotion > Auth > Settings > System > Theme > Guard > ACL), layout resolution

**Print Agent Entry:**
- Location: `print-agent/src/index.js`
- Triggers: `npm run dev:print`
- Responsibilities: Connect WebSocket to backend `/realtime`, listen for `print_invoice` events, output ESC/POS to thermal printer

**Root Monorepo:**
- Location: `package.json` (root)
- Commands: `npm run dev` (concurrent api+app), `npm run dev:all` (api+app+print)

## Error Handling

**Strategy:** Global exception filter + per-module try/catch

**Patterns:**
- `AllExceptionsFilter` (`api-ventago/src/common/filters/all-exceptions.filter.ts`): Catches all unhandled errors, logs via Winston, returns structured JSON error response. 500s include stack trace in response (debug mode).
- `ValidationPipe` with `whitelist: true, forbidNonWhitelisted: true`: Rejects unknown fields in DTOs automatically
- Frontend `api.service.ts` interceptor: Catches 401/403 responses, triggers logout + redirect. Special handling for `SESSION_EXPIRED` code.
- Winston logging: Errors logged to file via `api-ventago/src/common/logger/logger.config.ts`

## Cross-Cutting Concerns

**Logging:**
- Backend: Winston (`nest-winston`) with file rotation. `HttpLoggerMiddleware` logs all HTTP requests/responses. `AllExceptionsFilter` logs all errors.
- Frontend: `console.log` with `[AUTH:...]` prefixes for auth flow debugging. PostHog for analytics.

**Validation:**
- Backend: class-validator DTOs + global `ValidationPipe`. Each module has `dto/` folder with validation classes.
- Frontend: React Hook Form + Yup schemas for form validation.

**Authentication:**
- Backend: JWT (Passport) + SessionGuard (optional per-controller). `api-ventago/src/app/auth/strategies/jwt.strategy.ts` for JWT extraction.
- Frontend: `AuthContext` manages token lifecycle. `AuthGuard` (`ventago-app/src/@core/components/auth/AuthGuard.tsx`) wraps protected pages. `GuestGuard` for login page.

**Authorization:**
- Backend: `UserRoleGuard` (`api-ventago/src/app/auth/guards/user-role.guard.ts`) for role-based access
- Frontend: CASL `AclGuard` (`ventago-app/src/@core/components/auth/AclGuard.tsx`) with abilities built from user roles (`ventago-app/src/configs/acl.ts`). `useHasFunction` hook (`ventago-app/src/hooks/useHasFunction.ts`) for function-level permission checks.

**File Upload:**
- MinIO service at `api-ventago/src/common/minio/minio.service.ts`
- Accessed via `MinioModule` import. Controller at `api-ventago/src/common/minio/minio.controller.ts` serves files.
- Frontend: `apiConnector.sendFile()` / `apiConnector.putFile()` for multipart uploads

---

*Architecture analysis: 2026-04-01*
