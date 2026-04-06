# Codebase Structure

**Analysis Date:** 2026-04-01

## Directory Layout

```
ACE_online_1.0/                    # Monorepo root (npm workspaces)
├── api-ventago/                   # NestJS backend (submodule, port 5002)
│   ├── src/
│   │   ├── app/                   # Business domain modules
│   │   ├── common/                # Shared infrastructure (guards, filters, decorators, minio, socket)
│   │   ├── config/                # Environment config loader
│   │   ├── database/              # Sequelize DB module + migrations
│   │   ├── app.module.ts          # Root NestJS module
│   │   └── main.ts                # Bootstrap entry point
│   ├── logs/                      # Winston log files
│   ├── docker-compose.yml         # Backend Docker config
│   └── package.json
├── ventago-app/                   # Next.js frontend (submodule, port 3000/5001)
│   ├── src/
│   │   ├── @core/                 # Template framework (layouts, theme, base components)
│   │   ├── @fake-db/              # Mock data (mostly unused)
│   │   ├── assets/                # Static assets (icons)
│   │   ├── components/            # Shared reusable UI components
│   │   ├── configs/               # App configuration (auth, ACL, theme, i18n, roles)
│   │   ├── context/               # React contexts (Auth, System)
│   │   ├── hooks/                 # Custom hooks
│   │   ├── iconify-bundle/        # Icon bundle
│   │   ├── layouts/               # App-specific layout overrides
│   │   ├── navigation/            # Sidebar navigation definitions
│   │   ├── pages/                 # Next.js pages (routes)
│   │   ├── services/              # API client and service modules
│   │   ├── store/                 # Redux store (minimal)
│   │   ├── types/                 # TypeScript type definitions
│   │   ├── utils/                 # Utility functions
│   │   └── views/                 # Feature view components (main UI logic)
│   ├── styles/                    # Global CSS
│   ├── docker-compose.yml         # Frontend Docker config
│   └── package.json
├── print-agent/                   # Thermal printer agent (submodule)
│   ├── src/
│   │   ├── index.js               # WebSocket client entry
│   │   ├── formatter.js           # Invoice -> ESC/POS formatter
│   │   └── printer.js             # Printer connection/output
│   ├── config.json                # Printer/server config
│   └── package.json
├── docs/                          # Documentation files
├── scripts/                       # Build/deployment scripts
├── package.json                   # Root workspace config
└── package-lock.json
```

## Directory Purposes

### Backend: `api-ventago/src/app/`

Each subdirectory is a NestJS module with consistent internal structure:

```
api-ventago/src/app/{module}/
├── {module}.module.ts          # NestJS module definition
├── {module}.controller.ts      # REST API endpoints
├── {module}.service.ts         # Business logic
├── {module}.model.ts           # Sequelize model (DB table)
├── dto/                        # Request/response DTOs (class-validator)
│   ├── create-{module}.dto.ts
│   └── update-{module}.dto.ts
├── guards/                     # (optional) Module-specific guards
├── interfaces/                 # (optional) TypeScript interfaces
├── seed/                       # (optional) Seed data
└── {sub-entity}/               # (optional) Related sub-entities
```

**Core Business Modules:**
- `auth/` - JWT authentication, login, `/me` endpoint, strategies, guards
- `store/` - Store CRUD, logo upload, config, app management, integrations
- `branch/` - Branch (sucursal) management, default Box/Terminal creation
- `users/` - User CRUD, user-role assignment, user-function mapping
- `role/` - Role definitions, role-function mapping
- `products/` - Product CRUD, branch-specific products, categories
- `sales/` - Sales processing, sales-item, sales-payment, sales-discount, sales-recharge
- `stocks/` - Stock management
- `prices/` - Price types and price management
- `expenses/` - Expense tracking with categories/subcategories
- `box/` - Cash register (caja) management
- `box-operation/` - Box open/close/movement operations
- `caja-fuerte/` - Safe (vault) management
- `cashRegister/` - Cash register control
- `terminal/` - Terminal device management

**Supporting Modules:**
- `session/` - Active session enforcement, device fingerprint, IP registry
- `shared/` - Global vs Store data pattern (clients, categories, subcategories)
- `category/` - Category CRUD
- `subcategory/` - Subcategory CRUD
- `colors/` - Product colors
- `sizes/` - Product sizes
- `season/` - Product seasons
- `origin/` - Product origins
- `supplier/` - Supplier management
- `clients/` - Client management
- `sellers/` - Seller management
- `movements/` - Stock/inventory movements
- `discounts/` - Discount rules (payment-methods, product, reason, subcategory)
- `payment-methods/` - Payment method definitions + options
- `recharge/` - Recharge/surcharge management

**Advanced Feature Modules:**
- `production/` - Manufacturing (BOM, materials, work-orders, production-results)
- `subcon/` - Outsourcing (vendors, orders, deliveries, defects, material-issues, payments, settlements)
- `marketplace/` - Marketplace (config, product-visibility, public-products, public-purchase)
- `revendedor/` - Reseller portal (auth, categories, products, purchase, guards, strategies)
- `chat/` - AI chat (knowledge base, LLM integration)
- `team-chat/` - Internal team messaging

**Infrastructure Modules:**
- `audit-log/` - Audit trail logging
- `notifications/` - Notification system
- `reports/` - Report generation
- `dashboards/` - Dashboard data (admin, products, sales)
- `config/` - Store configuration settings
- `apps/` - App definitions (with seed data)
- `modules/` - Module definitions (with seed data)
- `functions/` - Function definitions (with seed data)
- `module-alias/` - Module alias mapping
- `seeders/` - Database seeder orchestration
- `nation/` - Country data (with seed)
- `province/` - Province/state data
- `subscription-config/` - Subscription plan configuration
- `support-token/` - Support access token generation
- `store-billing/` - Store billing management
- `suspended-sales/` - Suspended/held sales

### Backend: `api-ventago/src/common/`

- `crud/` - Base CRUD module (currently empty shell)
- `decorators/` - Custom decorators: `audit.decorator.ts` (`@Audit()`)
- `dto/` - Shared DTOs
- `excel/` - Excel export utilities
- `filters/` - `all-exceptions.filter.ts` (global error handler)
- `interceptors/` - `audit.interceptor.ts` (global audit logging)
- `logger/` - `logger.config.ts` (Winston configuration)
- `middleware/` - `http-logger.middleware.ts` (request/response logging)
- `minio/` - MinIO file storage: `minio.module.ts`, `minio.service.ts`, `minio.controller.ts`
- `socket/` - WebSocket: `websocket.module.ts`, `websocket.gateway.ts`, `websocket.service.ts`
- `utils/` - Shared utility functions

### Frontend: `ventago-app/src/pages/`

Next.js Pages Router - each directory = route. Pages are thin wrappers that render views.

**Public Pages:**
- `login/` - Login page
- `register/` - Store registration
- `olvidaste-contrasena/` - Password recovery
- `verifica-correo/` - Email verification

**POS & Sales:**
- `nueva-venta/` - POS sale screen (main selling interface)
- `ventas/` - Sales history list + `detalle/` detail view

**Inventory & Products:**
- `productos/` - Product management
- `precios/` - Price management

**Finance:**
- `gastos/` - Expense management
- `caja/` - Cash register + `detalle/` detail
- `caja-fuerte/` - Safe/vault
- `control-de-caja/` - Cash register control + `detalle/`

**Management:**
- `sucursales/` - Branch management
- `usuarios/` - User management
- `talleres/` - Workshop/outsourcing (`vendors/`, `pedidos/`, `dashboard/`)
- `configuracion/` - Settings (`productos/`, `ventas/`)
- `perfil/` - User profile

**Analytics:**
- `dashboards/` - Dashboards (`admin/`, `ventas/`, `producto/`, `stock/`, `fabrica/`, `talleres/`)
- `reportes/` - Reports (`ventas/`, `items/`, `stocks/`, `dashboards/`)

**Admin:**
- `admin/` - Super admin (`tiendas/`, `registros/`, `auditoria/`, `suscripcion/`, `permisos/`, `ventas/`)

**Special:**
- `cliente-vista/` - Customer-facing display
- `codigo-vista/` - Barcode/QR view
- `acl/` - ACL test page

### Frontend: `ventago-app/src/views/`

Feature view components - the main UI logic lives here. Each view directory corresponds to a page.

```
views/
├── admin/           # Admin views (audit, permissions, registration, stores, subscription, salesByStore)
├── box/             # Cash register views + components/
├── branches/        # Branch management views + components/
├── caja-fuerte/     # Safe views + components/ + hooks/
├── cash-control/    # Cash control (detail/, hooks/, list/)
├── cliente-vista/   # Customer display view
├── codigo-vista/    # Barcode view
├── commons/         # Shared view components (auth/)
├── config/          # Configuration views (TypePrices/, productos/, ventas/)
├── dashboards/      # Dashboard views (admin/, producto/, ventas/)
├── expenses/        # Expense views + components/
├── forward-password/# Password recovery view
├── homes/           # Home/landing view + components/ + hook/
├── login/           # Login view
├── pages/           # Static pages (auth/, misc/)
├── prices/          # Price management views + components/
├── products/        # Product views (hook/, list/)
├── profile/         # Profile views + components/
├── register/        # Registration views + components/
├── reports/         # Report views (products/, sales/, stocks/)
├── sales/           # Sales views (details/, list/)
├── talleres/        # Workshop views (pedidos/, vendors/)
├── users/           # User views (components/, roles/)
└── [feature]/       # Each feature view mirrors its page
```

### Frontend: `ventago-app/src/components/`

Shared reusable components:
- `boxes/` - Box/cash register components
- `buttons/` - Custom button components
- `cards/` - Card layouts
- `chat/` - AI chat widget
- `chips/` - Status chips
- `dialogs/` - Dialog/modal components
- `errors/` - Error display components
- `filters/` - Filter UI components
- `forms/` - Shared form components
- `images/` - Image display components
- `modals/` - Modal wrappers
- `reminders/` - Reminder/notification components
- `table/` - Data table components
- `team-chat/` - Team chat components
- `ui/` - Base UI primitives

## Key File Locations

**Entry Points:**
- `api-ventago/src/main.ts`: Backend bootstrap (port 5002, global prefix `/api`)
- `api-ventago/src/app.module.ts`: Root NestJS module with all imports
- `ventago-app/src/pages/_app.tsx`: Frontend app wrapper (provider stack)
- `print-agent/src/index.js`: Print agent WebSocket client

**Configuration:**
- `package.json` (root): Monorepo workspace scripts
- `api-ventago/src/config/env.config.ts`: DB config loader
- `api-ventago/src/database/database.module.ts`: Sequelize connection + global `underscored: true`
- `api-ventago/src/common/logger/logger.config.ts`: Winston logger config
- `ventago-app/src/configs/auth.ts`: Auth endpoint config
- `ventago-app/src/configs/acl.ts`: CASL permission definitions
- `ventago-app/src/configs/themeConfig.ts`: MUI theme settings
- `ventago-app/src/configs/i18n.ts`: Internationalization config
- `ventago-app/src/configs/roles.ts`: Role definitions
- `ventago-app/next.config.js`: Next.js config (webpack alias for apexcharts)

**Core Logic:**
- `ventago-app/src/services/api.service.ts`: Axios client with token/session interceptors
- `ventago-app/src/context/AuthContext.tsx`: Authentication state and login/logout flow
- `ventago-app/src/navigation/vertical/index.ts`: Dynamic sidebar nav from `user.structure`
- `api-ventago/src/app/auth/auth.service.ts`: Login, JWT issuance, `/me` endpoint
- `api-ventago/src/app/session/session.service.ts`: Session enforcement, device/IP validation
- `api-ventago/src/common/socket/websocket.gateway.ts`: WebSocket event handlers

**Guards & Middleware:**
- `api-ventago/src/app/auth/strategies/jwt.strategy.ts`: JWT Passport strategy
- `api-ventago/src/app/auth/guards/user-role.guard.ts`: Role-based access guard
- `api-ventago/src/app/session/guards/session.guard.ts`: Session token validation guard
- `api-ventago/src/common/middleware/http-logger.middleware.ts`: Request/response logging
- `ventago-app/src/@core/components/auth/AuthGuard.tsx`: Frontend auth route guard
- `ventago-app/src/@core/components/auth/AclGuard.tsx`: Frontend ACL guard
- `ventago-app/src/configs/withAuth.tsx`: HOC for auth-required pages
- `ventago-app/src/configs/withAccess.tsx`: HOC for access-controlled pages
- `ventago-app/src/configs/withFunctionAccess.tsx`: HOC for function-level access

**Database:**
- `api-ventago/src/database/database.module.ts`: Sequelize async config
- `api-ventago/src/database/migrations/`: Migration files

## Naming Conventions

**Files (Backend):**
- Module: `{name}.module.ts` (e.g., `sales.module.ts`)
- Controller: `{name}.controller.ts`
- Service: `{name}.service.ts`
- Model: `{name}.model.ts`
- DTO: `create-{name}.dto.ts`, `update-{name}.dto.ts`
- Guard: `{name}.guard.ts`

**Files (Frontend):**
- Pages: `index.tsx` inside route directory (e.g., `pages/ventas/index.tsx`)
- Views: PascalCase or descriptive name (e.g., `LoginView.tsx`, `SalesListView.tsx`)
- Components: PascalCase (e.g., `SidebarFooter.tsx`)
- Services: `{name}.service.ts`
- Hooks: `use{Name}.ts` or `use{Name}.tsx`
- Configs: camelCase `.ts` (e.g., `themeConfig.ts`, `acl.ts`)

**Directories:**
- Backend modules: kebab-case (e.g., `caja-fuerte/`, `box-operation/`, `payment-methods/`)
- Frontend pages: kebab-case Spanish (e.g., `nueva-venta/`, `control-de-caja/`)
- Frontend views: kebab-case English (e.g., `cash-control/`, `caja-fuerte/`)

## Where to Add New Code

**New Backend Feature (e.g., new business domain):**
1. Create directory: `api-ventago/src/app/{feature-name}/`
2. Create model: `{feature-name}.model.ts` (Sequelize `@Table` with `store_id` FK)
3. Create DTOs: `dto/create-{feature-name}.dto.ts`, `dto/update-{feature-name}.dto.ts`
4. Create service: `{feature-name}.service.ts`
5. Create controller: `{feature-name}.controller.ts`
6. Create module: `{feature-name}.module.ts` (import `SequelizeModule.forFeature([Model])`)
7. Register module in `api-ventago/src/app.module.ts`

**New Frontend Page:**
1. Create route directory: `ventago-app/src/pages/{page-name}/index.tsx` (thin wrapper)
2. Create view: `ventago-app/src/views/{feature-name}/` with main view component
3. Add to navigation if needed: `ventago-app/src/navigation/vertical/index.ts` (or add module in backend `apps/modules` seed)

**New Shared UI Component:**
- Place in `ventago-app/src/components/{category}/` (e.g., `dialogs/`, `forms/`, `table/`)

**New API Service Call (Frontend):**
- Use `apiConnector` from `ventago-app/src/services/api.service.ts`
- Tokens and headers are auto-injected by interceptors

**New Utility Function:**
- Backend: `api-ventago/src/common/utils/`
- Frontend: `ventago-app/src/utils/`

**New Custom Hook:**
- Place in `ventago-app/src/hooks/` for global hooks
- Place in `ventago-app/src/views/{feature}/hooks/` or `ventago-app/src/views/{feature}/hook/` for feature-specific hooks

## Special Directories

**`ventago-app/src/@core/`:**
- Purpose: Template framework code (Materio theme base)
- Generated: Originally from template, customized
- Committed: Yes
- **Avoid modifying** unless changing layout/theme system. Layout overrides go in `ventago-app/src/layouts/`

**`ventago-app/src/@fake-db/`:**
- Purpose: Mock data for development (mostly unused, commented out in `_app.tsx`)
- Generated: From template
- Committed: Yes

**`api-ventago/src/database/migrations/`:**
- Purpose: Database schema migrations
- Generated: Manually created
- Committed: Yes

**`node_modules/` (root):**
- Purpose: All workspace dependencies hoisted here by npm workspaces
- Generated: Yes (`npm install`)
- Committed: No
- **Important:** Packages may not exist in workspace-level `node_modules/`. Use `require.resolve()` for webpack aliases.

**`api-ventago/logs/`:**
- Purpose: Winston log files
- Generated: At runtime
- Committed: No

**Submodules:**
- `api-ventago/`, `ventago-app/` are Git submodules with their own repositories
- Root repo tracks submodule refs
- Push scripts: `push-both.sh`, `commit-both.sh`, `commit-both-auto.sh`

---

*Structure analysis: 2026-04-01*
