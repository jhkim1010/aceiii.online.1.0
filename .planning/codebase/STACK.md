# Technology Stack

**Analysis Date:** 2026-04-01

## Languages

**Primary:**
- TypeScript 5.7.3 - Backend (api-ventago), strict mode with `strictNullChecks`, `noImplicitAny`
- TypeScript 5.0.4 - Frontend (ventago-app), strict mode enabled

**Secondary:**
- JavaScript (Node.js) - Print agent (`print-agent/src/index.js`), `next.config.js`

## Runtime

**Environment:**
- Node.js 20 (specified in `api-ventago/Dockerfile` and `ventago-app/Dockerfile`)

**Package Manager:**
- npm with workspaces (monorepo root `package.json` defines 3 workspaces)
- Lockfile: `package-lock.json` (generated at root level)

**Monorepo:**
- npm workspaces configured in root `package.json`
- Workspaces: `api-ventago`, `ventago-app`, `print-agent`
- Packages hoist to root `node_modules/` -- use `require.resolve()` for webpack alias paths, never hardcode `./node_modules/`

## Frameworks

**Core:**
- NestJS 11.0.1 - Backend REST API framework (`api-ventago/`)
- Next.js 13.3.2 - Frontend with Pages Router (`ventago-app/`)
- React 18.2.0 - UI rendering (`ventago-app/`)

**ORM/Database:**
- Sequelize 6.37.5 + sequelize-typescript 2.1.6 - ORM (`api-ventago/`)
- sequelize-cli 6.6.2 - Database migrations
- pg 8.13.1 - PostgreSQL driver

**Testing:**
- Jest 29.7.0 + ts-jest 29.2.5 - Backend unit tests
- Supertest 7.0.0 - Backend HTTP/E2E tests
- Config: inline in `api-ventago/package.json` under `"jest"` key

**Build/Dev:**
- SWC (`@swc/cli` 0.6.0, `@swc/core` 1.10.7) - Fast NestJS compilation
- NestJS CLI 11.0.0 - Backend scaffolding and build (`nest build`)
- concurrently 8.2.2 - Run api + app simultaneously in dev
- next build - Frontend production build

**Linting/Formatting:**
- ESLint 9.18.0 + typescript-eslint 8.20.0 - Backend (`api-ventago/eslint.config.mjs`)
- ESLint 8.36.0 + eslint-config-next 13.3.2 - Frontend (`ventago-app/.eslintrc.json`)
- Prettier 3.4.2 (backend), Prettier 2.8.4 (frontend)
- IMPORTANT: Frontend ESLint treats warnings as errors during build

## Key Dependencies

**Critical (Backend):**
- `@nestjs/jwt` 11.0.0 + `passport-jwt` 4.0.1 - JWT authentication
- `@nestjs/passport` 11.0.5 - Passport integration
- `@nestjs/schedule` 6.1.1 - Cron job scheduling
- `@nestjs/sequelize` 11.0.0 - Sequelize integration with NestJS DI
- `@nestjs/websockets` 11.1.8 + `@nestjs/platform-socket.io` 11.1.8 - WebSocket support
- `minio` 8.0.6 - S3-compatible object storage client
- `bcrypt` 5.1.1 - Password hashing
- `class-validator` 0.14.1 + `class-transformer` 0.5.1 - DTO validation
- `nest-winston` 1.10.2 + `winston` 3.19.0 + `winston-daily-rotate-file` 5.0.0 - Structured logging
- `exceljs` 4.4.0 - Excel report generation (`api-ventago/src/common/excel/excel.service.ts`)
- `googleapis` 171.4.0 - Google Drive API for knowledge base sync
- `multer` 2.0.2 - File upload handling

**Critical (Frontend):**
- `@mui/material` 5.12.2 + `@mui/lab` 5.0.0-alpha.128 - Material UI components
- `@mui/x-data-grid` 6.0.3 - Data tables
- `@reduxjs/toolkit` 1.9.5 + `react-redux` 8.0.5 - State management
- `react-hook-form` 7.43.9 + `@hookform/resolvers` 3.1.0 + `yup` 1.1.1 - Form handling + validation
- `@casl/ability` 6.5.0 + `@casl/react` 3.1.0 - Attribute-based access control
- `axios` 1.4.0 - HTTP client (wrapped in `apiConnector` at `ventago-app/src/services/api.service.ts`)
- `posthog-js` 1.290.0 - Product analytics (production only)
- `i18next` 22.4.15 + `react-i18next` 12.2.2 - Internationalization
- `socket.io-client` 4.8.3 - WebSocket client for real-time features
- `apexcharts-clevision` 3.28.5 - Charts (aliased as `apexcharts` via webpack + tsconfig)
- `@fullcalendar/*` 6.1.6 - Calendar components
- `date-fns` 2.30.0 + `luxon` 3.3.0 - Date utilities

**Print Agent:**
- `socket.io-client` 4.8.1 - Connects to backend WebSocket
- `escpos` 3.0.0-alpha.6 + `escpos-usb` + `escpos-network` - Thermal printer control

## Database

**Engine:** PostgreSQL 15 (Docker container `dbpostgres`, database name `ventago`)

**ORM Configuration** (`api-ventago/src/database/database.module.ts`):
- Dialect: `postgres`
- `autoLoadModels: true` - Models auto-registered
- `underscored: true` - camelCase model props map to snake_case DB columns
- `timestamps: true` - Auto `created_at`, `updated_at`
- `synchronize: false` - Migrations only, no auto-sync
- `logging: false` - SQL query logging disabled

**Migrations:** Sequelize CLI (`npx sequelize-cli db:migrate`)

**Connection Config** (`api-ventago/src/config/env.config.ts`):
- Host: `DATABASE_HOST` (default: `localhost`)
- Port: `DATABASE_PORT` (default: `5432`)
- Database: `DATABASE_NAME` (default: `ventago`)
- Username: `DATABASE_USER` (default: `postgres`)
- Password: `DATABASE_PASSWORD` (default: `postgres`)

## Authentication & Authorization

**Backend Auth:**
- JWT via `@nestjs/jwt` + `passport-jwt`
- Session security layer: `active_sessions` table enforces single-session per user
- Device fingerprint tracking: `terminal_devices` table
- IP-to-branch binding: `branch_ip_registries` table
- SessionGuard (`api-ventago/src/app/session/guards/session.guard.ts`) validates `x-session-token` header

**Frontend Auth:**
- Token stored in `localStorage` as `accessToken`
- Session token stored as `sessionToken`
- Branch ID stored as `selectedBranchId`
- All injected via Axios interceptor in `ventago-app/src/services/api.service.ts`
- CASL for attribute-based access control (role + permission checks)

## Configuration

**Environment:**
- `.env` files per workspace (backend has `.env`, `.env.example`, `.env.template`)
- `@nestjs/config` ConfigModule loads env vars at bootstrap
- Frontend uses `process.env.NODE_ENV` to toggle API host (dev: `localhost:5002`, prod: `newapi.coolsistema.com`)
- Backend env vars: `DATABASE_*`, `JWT_SECRET_KEY`, `PORT`, `MINIO_*`, `GOOGLE_DRIVE_FOLDER_ID`, `GOOGLE_SERVICE_ACCOUNT_KEY_BASE64`

**Build:**
- `api-ventago/nest-cli.json` - NestJS build config (SWC compiler, `deleteOutDir: true`)
- `api-ventago/tsconfig.json` - Target ES2021, CommonJS modules
- `ventago-app/tsconfig.json` - Target ES6, ESNext modules, path alias for `apexcharts`
- `ventago-app/next.config.js` - Webpack alias for apexcharts-clevision, Winston server logging

## Logging

**Backend:**
- Winston via `nest-winston` (`api-ventago/src/common/logger/logger.config.ts`)
- Daily rotate file transport (`winston-daily-rotate-file`)
- HTTP logger middleware applied to all routes (`api-ventago/src/common/middleware/http-logger.middleware.ts`)

**Frontend:**
- Winston configured in `ventago-app/next.config.js`
- Logs to `logs/combined-YYYY-MM-DD.log` (14 day retention) and `logs/error-YYYY-MM-DD.log` (30 day retention)
- `console.error` and `console.warn` intercepted and piped to log files

## Platform Requirements

**Development:**
- Node.js 20+
- PostgreSQL 15 (local or Docker)
- npm (workspace-aware)
- Run: `npm run dev` from root (starts both api + app via concurrently)

**Production:**
- Docker containers on server `srv803182`
- Backend: port 5002, Docker image based on `node:20`
- Frontend: port 5001 (mapped to container port 3000), Docker image based on `node:20-alpine`
- Shared Docker network: `coolsistema_network` (external)
- Jenkins CI/CD: `front-coolsistema` (frontend), `api-coolsistema` (backend)

---

*Stack analysis: 2026-04-01*
