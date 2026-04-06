# External Integrations

**Analysis Date:** 2026-04-01

## APIs & External Services

**Object Storage (MinIO):**
- S3-compatible file storage for product images, store logos, documents
- SDK: `minio` 8.0.6 (Node.js client)
- Service: `api-ventago/src/common/minio/minio.service.ts`
- Module: `api-ventago/src/common/minio/minio.module.ts`
- Controller (proxy): `api-ventago/src/common/minio/minio.controller.ts`
- Auth env vars: `MINIO_HOST`, `MINIO_PORT`, `MINIO_BUCKET`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`
- Frontend image URL pattern: `{API_HOST}/minio/{fileName}`
- Used by: Store module (`store.module.ts`), Products module (`products.module.ts`)
- Usage pattern: Import `MinioModule` in feature module, inject `MinioService`, call `uploadFile(file, fileName)`

**Google Drive API:**
- Knowledge base document sync for AI chat feature
- SDK: `googleapis` 171.4.0
- Service: `api-ventago/src/app/chat/knowledge/drive-sync.service.ts`
- Auth: Google Service Account (base64-encoded key in `GOOGLE_SERVICE_ACCOUNT_KEY_BASE64`)
- Config env var: `GOOGLE_DRIVE_FOLDER_ID`
- Scope: `https://www.googleapis.com/auth/drive.readonly`
- Cron: Syncs every 10 minutes (`@Cron('*/10 * * * *')`)
- Supports: Google Docs, Sheets, PDF, Word, plain text, CSV, JSON, Markdown

**Product Analytics (PostHog):**
- User behavior tracking (production only)
- SDK: `posthog-js` 1.290.0
- Service: `ventago-app/src/services/posthog.service.ts`
- Init: `ventago-app/src/pages/_app.tsx`
- API host: `https://us.i.posthog.com`
- Tracks: agency name, email (via `posthog.people.set`)
- Disabled in development (`NODE_ENV === 'development'`)

## Data Storage

**Database:**
- PostgreSQL 15
- Docker container name: `dbpostgres`
- Database name: `ventago`
- Connection env vars: `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD`
- ORM: Sequelize 6 + sequelize-typescript (NestJS integration via `@nestjs/sequelize`)
- Config: `api-ventago/src/database/database.module.ts`
- Migrations: `api-ventago/src/database/migrations/` via sequelize-cli

**File Storage:**
- MinIO (S3-compatible) for all file uploads (images, documents)
- No local filesystem storage in production

**Caching:**
- None detected -- no Redis, Memcached, or in-memory cache layer

## Real-Time Communication

**WebSocket (Socket.io):**
- Backend gateway: `api-ventago/src/common/socket/websocket.gateway.ts`
- Backend service: `api-ventago/src/common/socket/websocket.service.ts`
- Module: `api-ventago/src/common/socket/websocket.module.ts`
- Namespace: `/realtime`
- CORS: `origin: '*'`

**Events:**
- `register_api_key` - Print agent registers with API key
- `register_user` - Frontend registers user for team chat (userId + storeId)
- `print_confirmation` - Print agent confirms print job
- `welcome` - Sent on connection

**Emit Methods:**
- `emitToApiKey(apiKey, event, payload)` - Send to specific API key group (print agents)
- `emitToUser(userId, event, payload)` - Send to specific user (notifications, chat)
- `emitToStore(storeId, event, payload)` - Broadcast to all users in a store
- `emitToAll(event, payload)` - Global broadcast

**Frontend Client:**
- `socket.io-client` 4.8.3 in ventago-app
- Team chat panel: `ventago-app/src/components/team-chat/TeamChatPanel.tsx`

**Print Agent:**
- `socket.io-client` 4.8.1 in print-agent
- Connects to backend WebSocket, listens for print commands
- Drives thermal printers via `escpos` library (USB and network)
- Config: `print-agent/config.json`

## Authentication & Identity

**Auth Provider:** Custom JWT implementation
- Module: `api-ventago/src/app/auth/`
- Strategy: Passport JWT (`passport-jwt`)
- Token: Bearer token in `Authorization` header
- Session: UUID v4 `sessionToken` in `x-session-token` header
- Branch context: `x-branch-id` header

**Session Security System** (`api-ventago/src/app/session/`):
- Single-session enforcement (one active session per user)
- Device fingerprint tracking (browser SHA-256 hash)
- IP-to-branch binding
- Guard: `api-ventago/src/app/session/guards/session.guard.ts`

**Frontend Auth Flow** (`ventago-app/src/services/api.service.ts`):
- Axios interceptor auto-injects `Authorization`, `x-session-token`, `x-branch-id` headers
- On 401 `SESSION_EXPIRED`: clears session, redirects to `/login?reason=session_expired`
- On any 401/403: calls `authService.logout()`, redirects to `/`

**Authorization:**
- CASL (`@casl/ability` + `@casl/react`) for attribute-based access control on frontend
- Role/permission system in backend (`api-ventago/src/app/role/`, `api-ventago/src/app/users/user-role/`)

## Scheduled Jobs

**Cron Jobs** (via `@nestjs/schedule`):
- Google Drive sync: every 10 minutes (`api-ventago/src/app/chat/knowledge/drive-sync.service.ts`)
- Store cron tasks: `api-ventago/src/app/store/store.cron.ts`
- Reports scheduling: `api-ventago/src/app/reports/reports.schedule.ts`
- Schedule module initialized in `api-ventago/src/app.module.ts` via `ScheduleModule.forRoot()`

## Excel/Report Generation

**ExcelJS:**
- Service: `api-ventago/src/common/excel/excel.service.ts`
- Used for generating downloadable Excel reports

## Internationalization

**i18next:**
- Frontend only: `i18next` 22.4.15 + `react-i18next` 12.2.2
- Browser language detection: `i18next-browser-languagedetector` 7.0.1
- HTTP backend for translations: `i18next-http-backend` 2.2.0

## Monitoring & Observability

**Error Tracking:**
- No dedicated error tracking service (no Sentry, Datadog, etc.)
- Errors logged to Winston file transports

**Logs:**
- Backend: Winston with daily rotate file (`nest-winston`)
- Frontend: Winston with daily rotate file (configured in `next.config.js`)
- HTTP request/response logging middleware on all backend routes

## CI/CD & Deployment

**Hosting:**
- Self-hosted server: `srv803182`
- Docker containers on shared network `coolsistema_network`
- Backend URL: `https://newapi.coolsistema.com/api` (port 5002)
- Frontend URL: `https://ventago.coolsistema.com` (port 5001 -> 3000)

**CI Pipeline:**
- Jenkins (external, no Jenkinsfile in repo)
- Frontend job: `front-coolsistema`
- Backend job: `api-coolsistema`
- Build process: `docker compose build` -> `npm run build`
- Build logs stored as `#NNN.txt` files

**Docker Configuration:**
- Backend: `api-ventago/Dockerfile` (node:20, port 5002, dev mode CMD)
- Backend compose: `api-ventago/docker-compose.yml` (volume mount for hot reload)
- Frontend: `ventago-app/Dockerfile` (node:20-alpine, production build, non-root user)
- Frontend compose: `ventago-app/docker-compose.yml` (port 5001:3000)

## Environment Configuration

**Required env vars (Backend):**
- `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD` - PostgreSQL
- `JWT_SECRET_KEY` - JWT signing
- `PORT` - Server port (default 5002)
- `MINIO_HOST`, `MINIO_PORT`, `MINIO_BUCKET`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` - File storage

**Optional env vars (Backend):**
- `GOOGLE_DRIVE_FOLDER_ID` - Knowledge base sync folder
- `GOOGLE_SERVICE_ACCOUNT_KEY_BASE64` - Google API auth

**Frontend env:**
- `NODE_ENV` - Switches API host between dev (`localhost:5002`) and prod (`newapi.coolsistema.com`)
- PostHog key hardcoded in `ventago-app/src/services/posthog.service.ts` (production only)

**Secrets location:**
- `.env` files in each workspace (gitignored)
- Templates: `api-ventago/.env.example`, `api-ventago/.env.template`
- Docker compose references `.env` via `env_file` directive

## API Design

**Backend API Pattern:**
- RESTful endpoints under `/api` prefix
- NestJS controllers with standard CRUD operations
- DTO validation via `class-validator` decorators
- File uploads via `multer` middleware
- API key header: `x-api-key` (hardcoded `12345` in frontend -- for internal use)

**Frontend API Client** (`ventago-app/src/services/api.service.ts`):
```typescript
apiConnector.get<T>(path, params)     // GET with query params
apiConnector.post(path, body)          // POST JSON
apiConnector.put(path, body)           // PUT JSON
apiConnector.remove(path, params)      // DELETE
apiConnector.sendFile(path, formData)  // POST multipart
apiConnector.putFile(path, formData)   // PUT multipart
apiConnector.downloadFile(path, fileName, params)  // GET blob + auto-download
```

## Webhooks & Callbacks

**Incoming:**
- None detected

**Outgoing:**
- None detected

---

*Integration audit: 2026-04-01*
