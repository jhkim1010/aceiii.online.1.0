# Phase 96: Notas compartidas del local - Research

**Researched:** 2026-09-28
**Domain:** NestJS/Sequelize backend module + Next.js frontend page, multitenant store-scoped messaging/ack feature
**Confidence:** HIGH (all core claims verified against repo code, not training knowledge)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Notas는 Team Chat과 별개 기능이다. 채팅 = 흘러가는 대화, nota = 남는 기록.
  테이블·화면은 새로 만들고, `/realtime` 소켓(`emitToUser`/`emitToStore`)과 매장 사용자 목록만 재사용한다.
  Team Chat(`team_messages`, `TeamChatBubble`)은 건드리지 않는다.
- **D-02:** 화면 형태 = B · 받은편지함형 2칸(2026-09-28 목업 비교 후 사용자 선택). 왼쪽 목록
  (보낸이 → 대상 · 시각 · 제목 · 본문 한 줄, 고정·안읽음 점·중요도 색 띠), 오른쪽 선택한 nota 본문 +
  Entendido 게이트 · 반응 · 읽음 목록 · 답글 스레드. 좁은 화면에서는 목록 아래로 본문이 쌓인다.
  기준 목업: `.planning/sketches/notas-compartidas.html` (「B · Bandeja」). A(카드)는 채택하지 않음.
- **D-03:** 「Todos」 발송은 권한(function)으로 제어한다(예: slug `notas-enviar-todos`). 기본값은
  admin 역할만 부여. 개인·일부 대상 발송은 Notas 메뉴에 접근할 수 있는 사용자 누구나 가능.
- **D-04:** 대상은 Todos 또는 1명 이상 선택한 사용자. 1명이면 개인 nota. 지점 단위 발송은 없음.
- **D-05:** 개인·일부 대상 nota는 보낸 사람과 받는 사람만 본다. 매장 admin도 볼 수 없다
  (서버가 조회 시 거른다 — 프론트 숨김이 아니라 API가 거절).
- **D-06:** nota 형식 = 제목(필수) + 본문 + 중요도(`Normal` / `Importante` / `Urgente`). 카테고리 없음.
- **D-07:** 「Todos」 = 매장의 공용 기록. 나중에 입사한 사용자도 과거 Todos nota를 본다.
  단, 신입에게 과거 nota가 전부 「안읽음」으로 쌓이지 않게 한다 — 신입의 안읽음 대상은 고정(Fijada)
  nota와 입사 이후 nota 뿐.
- **D-08:** 새 nota 알림 = 사이드바 「Notas」 옆 안읽음 개수 배지 + 소켓 실시간 토스트
  (클릭하면 해당 nota 열림).
- **D-09:** POS(`nueva-venta`) 화면에서는 배지만, 토스트·팝업 없음(판매 중 포커스·단축키를 빼앗지
  않는다). Urgente도 동일.
- **D-10:** 보낸 사람에게 읽은 사람 / 안 읽은 사람 목록(「3/7 leído」 + 이름·시각). Todos nota는
  매장 admin도 볼 수 있다(개인 nota는 D-05에 따라 당사자만).
- **D-11:** 읽음 기준 — `Normal`은 본문을 열면 읽음. `Importante`·`Urgente`는 「Entendido」 버튼을
  눌러야 「확인함」. (열람과 확인을 구분해 기록: 열람 시각 / 확인 시각)
- **D-12:** 반응 = 고정 5개 👍 ✅ 👀 ❤️ 😂. 한 사람이 여러 개 가능, 다시 누르면 취소, 호버로
  누가 눌렀는지.
- **D-13:** 답글 = 한 단계 스레드(답글의 답글 없음). nota를 볼 수 있는 사람 전원이 답글을 본다
  (Todos → 모두, 개인 → 당사자들). 답글에도 반응 가능. 답글이 달리면 nota 참여자(작성자 + 대상)에게
  알림/배지.
- **D-14:** 수정 = 가능, 「editado」 표시 + 이전 내용 이력 보존. 삭제 = 소프트 삭제(「Archivada」)
  — 목록에서 빠지고 기록은 남음. 매장 admin은 남의 Todos nota도 보관 처리할 수 있다
  (개인 nota는 불가 — D-05).
- **D-15:** 상단 고정(Fijar) — Todos nota는 D-03의 Todos 발송 권한자가 고정. 개인 nota는 받는
  사람이 자기 목록에서만 고정.
- **D-16:** 만료일(선택) — 지나면 목록·배지·고정에서 빠지고 「Vencidas」 필터로 조회. 삭제하지
  않는다. 날짜 판정은 매장 타임존 기준(DB는 UTC — `stores.timezone`).
- **D-17:** 첨부 = 사진 + PDF, nota당 최대 5개(이미지는 미리보기, PDF는 링크). 답글에는 사진 1개.
  MinIO 저장. 크기 상한은 기존 업로드 상한을 따른다(nginx · 앱 상수 · multer 3층 확인).
- **D-18:** 검색 — 제목·본문으로 지난 nota 검색. 검색 결과도 D-05 가시성 규칙을 그대로 따른다.
- **D-19:** 탭 = Todas · Para mí(안읽음 개수) · Enviadas · Archivadas · Vencidas — 목업 그대로
  (사용자 이견 없음). 기본 정렬: 고정 → 안읽음 → 최신.

### Claude's Discretion

- 테이블 설계(nota · 대상 · 읽음/확인 · 반응 · 답글 · 첨부 · 수정 이력), 인덱스, 페이지네이션(pageSize ≤ 50).
- 토스트 컴포넌트·배지 폴링/소켓 갱신 방식, SWR 키 설계.
- 권한 slug 이름과 시드 마이그레이션 구성(단, 사이드바는 structure 시드가 코드보다 먼저 나가야 한다).
- 소켓 이벤트 이름(`nota:new`, `nota:reply`, `nota:reaction` 등).

### Deferred Ideas (OUT OF SCOPE)

- 지점(sucursal) 단위 발송 — 이번에는 Todos / 사용자 선택만.
- 카테고리 분류 — 이번에는 중요도만.
- 다단계 스레드 · 자유 이모지.
</user_constraints>

<phase_requirements>
## Phase Requirements

No formal REQ-IDs were issued for this phase; CONTEXT.md's D-01..D-19 function as the requirement set. Mapping:

| ID | Description | Research Support |
|----|-------------|------------------|
| D-01 | Separate from Team Chat, reuse `/realtime` socket + user list | §Reusable Assets, §Realtime confirms `emitToUser`/`emitToStore` API and that `team_messages`/`TeamChatBubble` need zero changes |
| D-02 | Bandeja (2-column) layout per approved sketch | §UI Contract — sketch is the literal spec, read its JS state machine directly |
| D-03 | `notas-enviar-todos` function gate, admin-only by default | §Permission Seed — template from `2026-09-27-e-modulo-impresoras.sql` |
| D-04 | Todos or 1+ users, no branch-level | §Data Model — `nota_recipients` table |
| D-05 | Personal notes invisible to store admin, server-enforced | §Visibility Enforcement — tenant guard does NOT cover this, service-level WHERE required |
| D-06 | title+body+importance, no category | §Data Model |
| D-07 | New hires see past Todos but only pinned+post-hire unread | §Data Model + `users.created_at` confirmed |
| D-08/D-09 | Badge always, toast except on POS route | §Realtime, §Sidebar Badge Injection, §POS Suppression |
| D-10 | Read/ack list, Todos visible to admin | §Data Model — reads table with seen_at/ack_at |
| D-11 | Normal=seen, Importante/Urgente=ack (Entendido) | §Data Model |
| D-12/D-13 | 5 fixed reactions, 1-level replies | §Data Model |
| D-14 | Edit history, soft archive, admin can archive others' Todos | §Data Model — edit history table |
| D-15/D-16 | Pin, expiry in store timezone | §Timezone Handling — reuse `attendance-time.util.ts` |
| D-17 | Attachments via MinIO, 3-layer size limit, privacy | §Attachments and Privacy — CRITICAL finding on public MinIO serving |
| D-18 | Search title/body, same visibility rules | §Pagination/Search |
| D-19 | 5 tabs, pin→unread→recent sort | §Data Model, matches sketch `list()` function |
</phase_requirements>

## Summary

Phase 96 is a net-new NestJS module + Next.js page, closely modeled on the existing `team-chat`
module but with materially different requirements: per-recipient visibility that is **not**
covered by the repo's global tenant-isolation hook, a real read/ack/reaction/reply/edit-history
data model (team-chat's own "read tracking" is partially aspirational — `team_message_reads` is
referenced only in a comment, the table doesn't exist), and a permission-gated "send to all"
action that must follow the repo's proven seed-migration pattern (`role_functions` grants via
SQL, applied to prod **before** code deploy).

The most safety-critical findings are: (1) the store-wide `TenantGuard` hook auto-scopes every
query by `store_id` but has **no concept of per-row recipient visibility** — D-05 (admin cannot
see personal notes) must be enforced entirely in the Notas service's WHERE clauses, on every
read path including search; (2) the public `/minio/:filename` endpoint serves any flat-named,
non-blacklisted-extension file with **no auth check at all** — nota attachments must be stored
under a path prefix (e.g. `notas/{storeId}/...`) so the public endpoint's `isPubliclyServable()`
rejects them (it blocks any name containing `/`), and Notas needs its own authenticated,
visibility-checked download endpoint; (3) the sidebar's `badgeContent` field exists in the type
system but has zero producers today — wiring a live unread count into the memoized `Navigation`
tree is a new integration, not a copy of an existing pattern.

**Primary recommendation:** Build Notas as an independent module (`api-ventago/src/app/notas/`)
mirroring `team-chat`'s module/service/controller shape, but add an explicit visibility
predicate helper (`notaVisibleToUser(storeId, userId)`) applied in every service query;
seed the module/function/role_functions via a single reviewed SQL file styled after
`2026-09-24-phase93-p5-seed-herramientas.sql`, deployed before the code; store attachments under
a private path prefix and serve them through a new authenticated controller action, never the
public `/minio/:filename` route.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Nota CRUD, visibility filtering, ack/reaction/reply logic | API / Backend | Database | Business rules (D-05, D-07, D-11) must be enforced server-side; DB stores state |
| Store-level tenant isolation (`store_id`) | Database (via ORM hook) | API | Already automatic via `tenant-hooks.ts` for any model with `storeId` — no new code needed for this layer alone |
| Per-recipient/sender visibility (D-05) | API / Backend | — | NOT covered by tenant hook; must be explicit service-layer WHERE (sender OR recipient OR audience='all') |
| Realtime push (new nota, reply, reaction) | API / Backend (emit) | Browser/Client (listen) | `/realtime` gateway already authenticates and rooms by `user:{id}`/`store:{id}` |
| Sidebar unread badge | Browser/Client | API / Backend (unread count endpoint) | Badge lives in memoized `Navigation` tree; count is fetched/pushed from backend |
| Toast suppression on POS | Browser/Client | — | Pure client-side route check (`router.pathname === '/nueva-venta'`), no server involvement |
| Attachment storage | API / Backend (MinIO client) | Database (path metadata) | MinIO bucket is shared infra; access control must happen in API, not the public static route |
| Expiry date evaluation (store timezone) | API / Backend | — | DB is UTC; comparison must happen server-side using `stores.timezone`, never client `Date` |
| Menu/permission seed | Database (migration) | API (guard reads it) | `structure` used by frontend is derived entirely from DB seed + `role_functions` |

## Standard Stack

This phase adds no new third-party dependencies. Everything needed already exists in the
monorepo's installed stack (verified by grep, not registry lookup — internal reuse, not public
package selection):

### Core (reused, no install needed)
| Library | Version (installed) | Purpose | Why Standard (in this repo) |
|---------|---------|---------|--------------|
| `sequelize-typescript` | per `api-ventago/package.json` (already installed) | Nota/NotaRecipient/NotaRead/... models | Every other module uses this ORM style |
| `socket.io` / `socket.io-client` | already installed | Realtime push for new nota/reply/reaction | `/realtime` namespace already exists; do not create a new namespace |
| `minio` (npm) | already installed | Attachment storage | `MinioService` wraps it; reuse `uploadFile`/`getObjectStream` |
| MUI 5 | already installed | Bandeja UI (list + detail split) | Project-wide UI convention |

### Don't add
- Do not add a new WebSocket namespace (`/notas`) — reuse `/realtime`, new event names only
  (`nota:new`, `nota:reply`, `nota:reaction`, matching the "Claude's Discretion" note in CONTEXT).
- Do not add a rich-text or markdown library for the body — sketch shows plain text with
  `white-space: pre-line`; CONTEXT doesn't request rich text.
- Do not add a new date/timezone library — `attendance-time.util.ts` already has `storeNowParts`/
  `nextMidnightISO` using native `Intl`.

**Installation:** none required.

## Architecture Patterns

### System Architecture Diagram

```
[Browser: Notas page]                         [Browser: any page / POS]
   |  GET /notas?tab=..&q=..                     |  socket 'nota:new' event
   |  POST /notas (title,body,imp,to[])          |  (from shared /realtime socket)
   |  POST /notas/:id/ack | /read                |
   |  POST /notas/:id/reactions                  v
   |  POST /notas/:id/replies             [route check: is /nueva-venta?]
   |  PATCH /notas/:id (edit)                    |
   |  PATCH /notas/:id/archive                 yes -> update badge only
   |  PATCH /notas/:id/pin                      no  -> show toast + update badge
   v
[NestJS NotasController]  --@Auth()/@FunctionGuard('notas-enviar-todos','create')-->
   v
[NotasService]
   ├─ visibility predicate: sender=me OR audience='all' OR EXISTS(recipient=me)
   │    (applied to EVERY read: list, detail, search — D-05/D-18)
   ├─ write path: create Nota + NotaRecipient rows in one transaction
   ├─ ack/read: upsert NotaRead(notaId,userId,seenAt,ackAt)
   ├─ reaction: toggle NotaReaction(notaId|replyId,userId,emoji)
   ├─ reply: create NotaReply (1 level only — validate parent has no parent)
   ├─ edit: create NotaEditHistory snapshot before update, set editedAt
   └─ expiry check: compare stores.timezone "today" vs nota.expiresOn
   v
[TenantGuard ORM hook] -- auto-injects store_id on every query (existing, Phase 67)
   v
[PostgreSQL: nota, nota_recipients, nota_reads, nota_reactions, nota_replies,
              nota_edit_history, nota_attachments]
   |
   +--> [WebsocketService.emitToUser / emitToStore] -> `/realtime` room -> browser listeners
   |
   +--> [MinioService.uploadFile] -> bucket, path-prefixed key (notas/{storeId}/{notaId}/...)
             |
             v
        [NEW: authenticated GET /notas/attachments/:notaId/:filename]
             (checks visibility predicate before streaming — NEVER via public /minio/:filename)
```

### Recommended Project Structure
```
api-ventago/src/app/notas/
├── notas.module.ts
├── notas.controller.ts
├── notas.service.ts                # visibility predicate + all business rules
├── notas-attachments.controller.ts # authenticated attachment streaming (separate from MinioController)
├── models/
│   ├── nota.model.ts
│   ├── nota-recipient.model.ts
│   ├── nota-read.model.ts
│   ├── nota-reaction.model.ts
│   ├── nota-reply.model.ts
│   ├── nota-edit-history.model.ts
│   └── nota-attachment.model.ts
├── dto/
│   ├── create-nota.dto.ts
│   └── ...
└── notas.service.spec.ts           # harness pattern below

ventago-app/src/
├── pages/notas/index.tsx           # next/dynamic(..., { ssr: false })
├── views/notas/
│   ├── NotasPage.tsx               # tabs + search + split layout (D-02, D-19)
│   ├── NotaList.tsx
│   ├── NotaDetail.tsx
│   ├── ComposeNotaDialog.tsx
│   └── notas.types.ts
├── hooks/api/useNotasUnreadCount.ts # SWR hook, short dedup — feeds badge
└── components/notas/NotaToast.tsx   # mounted once in UserLayout, route-aware (D-09)
```

### Pattern 1: Tenant-guard-covered model + explicit visibility layer
**What:** Every Nota* model gets `storeId` so the existing `TenantGuard` hook (installed
automatically for any model with a `storeId` attribute — `tenant-hooks.ts:579-834`) restricts
queries to the caller's store with zero extra code. This is necessary but **not sufficient**:
the hook has no concept of "is this row addressed to me". D-05 requires an additional
service-level predicate.
**When to use:** Every query against `nota` (list, detail, search).
**Example (service-level visibility predicate):**
```ts
// Source: pattern inferred from tenant-hooks.ts comments + team-chat.service.ts structure
// (own composition — no direct precedent exists in repo for per-row recipient visibility)
private visibilityWhere(userId: number) {
  return {
    [Op.or]: [
      { senderId: userId },
      { audience: 'all' },
      { '$recipients.user_id$': userId }, // requires include: [{ model: NotaRecipient, as: 'recipients' }]
    ],
  };
}
```
**Why this can't be skipped:** `resolveModelPolicy()` in `tenant-scope.registry.ts` only knows
about `storeId`; it has no per-row ACL concept. Relying on it alone for D-05 would let a store
admin's queries return every Todos+personal nota in the store.

### Pattern 2: Seed-before-code permission rollout
**What:** A single reviewed SQL migration inserts `modules` → `functions` → `role_functions` →
`role_function_actions` rows, granting `notas-enviar-todos` to the admin role only, and a
view-only `ver-notas` function to all roles (mirrors `2026-09-27-e-modulo-impresoras.sql` and
`2026-09-24-phase93-p5-seed-herramientas.sql`).
**When to use:** Any new sidebar menu / FunctionGuard slug.
**Example:**
```sql
-- Source: api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql (verified in repo)
SET lock_timeout = '5s';

INSERT INTO modules (name, slug, description, icon, url, is_main, is_auxiliary, app_id, created_at, updated_at)
SELECT 'Notas', 'notas', 'Notas compartidas del local', 'tabler:notes', '/notas', true, false, a.id, now(), now()
FROM apps a WHERE a.slug = '<pick existing top-level app or create one>'
  AND NOT EXISTS (SELECT 1 FROM modules m WHERE m.slug = 'notas');
-- ... functions 'ver-notas' (all roles) + 'notas-enviar-todos' (admin role only) ...
-- ★ MUST deploy this SQL to prod BEFORE the code deploy (FunctionGuard denies unknown slugs — Phase 93 P1-e).
```
**Deviation from precedent to flag for planner:** both reference migrations hang their module
off an *existing* app (`admin`, `herramientas`). Notas is a main, operational, everyday feature
(not auxiliary) — it likely needs its own top-level nav entry, not a slot inside `herramientas`
(which is deliberately non-billed and `is_auxiliary`). Planner must pick which existing `app`
row to attach the `notas` module to (candidates: create a dedicated small app, or hang it off
whichever app is already universal to every role — the seed migration for `herramientas` notes
per-role app coverage gaps of up to 27/120 roles, so verify with a query before choosing).

### Pattern 3: Realtime via existing `/realtime` namespace, no new gateway
**What:** `WebsocketService.emitToUser(userId, 'nota:new', payload)` /
`emitToStore(storeId, 'nota:new', payload)`, exactly like `team-chat.service.ts:44-55`.
**Frontend:** `useRealtime('realtime', { 'nota:new': handler, 'nota:reply': handler, ... },
{ enabled: true, room: { event: 'register_user', payload: { userId, storeId } } })` — same hook
`TeamChatPanel.tsx` uses (`src/realtime` — the only sanctioned place to import
`socket.io-client`; do not import it directly anywhere else, an ESLint rule blocks it).
**Key difference from team-chat:** team-chat's listener is only mounted while `open` is true
(`enabled: Boolean(open && user?.id)`), so `TeamChatBubble`'s unread badge count is fetched by
**polling on open/close**, not by a persistent listener. Notas needs badge + toast to work even
when the Notas page isn't open (D-08 fires from any screen), so the socket listener must be
mounted globally (e.g. in `UserLayout`), always enabled while the user is logged in — closer to
how `NoticesBanner` or `ActingStoreBar` are always-mounted, `dynamic(..., {ssr:false})` components
in `UserLayout`.

### Anti-Patterns to Avoid
- **Trusting `TenantGuard` for D-05:** the hook only enforces store-level isolation; it will
  happily return another user's personal nota within the same store. Every query needs the
  explicit predicate.
- **Serving attachments through `/minio/:filename`:** that route is `@Public()` and has no
  visibility check at all — only a filename shape check. Any flat-named image is world-readable
  by anyone who can guess/observe the filename.
- **Polling for unread count only while the Notas page is open** (team-chat's pattern): breaks
  D-08 (badge visible from any screen) and D-09 (toast must fire from POS-adjacent screens too,
  just suppressed there specifically).
- **Registering role-permission grants without the `ON CONFLICT` NULL-safety caveat:** `roles`
  has 4 global rows with `store_id IS NULL` (vendedor/admin/superadmin/gerente, ids 1-4).
  `ON CONFLICT (role_id, function_id, store_id)` does **not** fire for NULL `store_id` (NULL ≠
  NULL in Postgres), producing duplicate rows on re-run. Use `NOT EXISTS (... store_id IS NOT
  DISTINCT FROM ...)` as the `2026-09-24` seed migration does.
- **A single global `badgeContent` recompute triggering the whole nav tree needlessly:** keep
  the unread-count state update path narrow (see §Sidebar Badge Injection pitfall below).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Store-level data isolation | Custom `WHERE store_id = ?` on every query | Just add `storeId` column to every Nota* model | `TenantGuard` hook auto-installs at boot for any model with a `storeId` attribute (`tenant-hooks.ts`) |
| Realtime transport | New Socket.IO namespace/gateway | `/realtime` namespace + `WebsocketService.emitToUser/emitToStore` | One physical connection per namespace is enforced by `socket-registry.ts`; a new namespace multiplies connections across 300+ stores |
| File storage | Direct filesystem writes | `MinioService.uploadFile()` | Already handles bucket/content-type; consistent with every other upload path in the repo |
| Page size clamping | Custom `Number(pageSize) || 10` | `clampPageSize()` from `src/common/pagination/pagination.util.ts` | Existing DoS backstop, used by `team-chat.controller.ts` |
| Store-local "today" for expiry | New Date() + manual offset math | `storeNowParts(timezone)` / `nextMidnightISO(timezone)` from `src/app/attendance/attendance-time.util.ts` | Already handles the UTC-DB / store-timezone boundary correctly; a hand-rolled version risks the daily-number-style TZ mismatch bug documented in that file's own comments |
| Auth/session context | Reading JWT manually in service | `@Auth()` + `@GetUser()` decorators | Standard across every controller in the repo |

**Key insight:** almost nothing in this phase needs new infrastructure — the risk is entirely in
*correctly composing* four already-existing systems (tenant guard, realtime rooms, MinIO public
route, permission seed) in a way that satisfies D-05's stricter-than-store visibility rule and
D-17's attachment privacy requirement. The hand-rolling risk here is building a *parallel*
mechanism (e.g., a second socket namespace, a second "isAdmin" check bypassing FunctionGuard)
instead of composing the existing ones correctly.

## Visibility Enforcement Deep Dive (D-05)

Verified in `api-ventago/src/common/tenant/tenant-hooks.ts` and `tenant-scope.registry.ts`:

- `installTenantGuard()` runs once at boot (`DatabaseModule.onModuleInit`) and installs
  `beforeFind`/`beforeCount`/`beforeCreate`/`beforeUpdate`/`beforeDestroy` hooks on **every**
  Sequelize model that has a `storeId` attribute. This will apply automatically to `Nota`,
  `NotaRecipient`, etc. as soon as they're registered — no explicit call needed.
- The predicate the hook injects is `storeId IN (allowedStores)` (`buildStorePredicate`). It has
  **no knowledge of `senderId`/`receiverId`-style columns.** Confirmed: nothing in
  `tenant-scope.registry.ts`'s `DERIVED_SCOPE` map or `GLOBAL_ROW_TABLES` set references any
  per-user recipient concept — the entire registry is store-shape only.
- Consequence for planning: the Notas service must add its own `Op.or` predicate (sender OR
  audience='all' OR EXISTS in `nota_recipients`) on top of whatever the tenant hook already adds
  as an AND. Sequelize will combine them (`mergeWhere` wraps existing `where` in `Op.and`), so
  this composes safely — the planner does not need to disable/bypass the tenant hook.
- `team-chat.service.ts` shows the existing but *weaker* version of this pattern: it manually
  builds an `Op.or` for the 1:1 case (`{senderId: userId, receiverId} OR {senderId: receiverId,
  receiverId: userId}`), proving this composition style is already idiomatic in this codebase.
- **Admin bypass trap (confirmed via `withAccess.tsx` reading):** `PRIVILEGED_ROLES` includes
  store `admin`, and `WithAccess`'s `isPrivileged` flag bypasses `allowedRoles`/`allowedApps`/
  `allowedModules`/`allowedFunctions` checks on the frontend. This is a **page-access** gate only
  — it has zero bearing on the Notas API's row-level filtering, but it does mean the frontend
  cannot be trusted to hide the "view any nota" temptation from an admin UI; the visibility
  predicate is the only real boundary, matching the CONTEXT.md note "서버가 조회 시 거절 — 프론트
  숨김이 아니라".
- **Role/store scoping trap (from project memory, apply here too):** `req.user.roles` is not
  guaranteed to be filtered by the active store for all code paths (`shapeAuthUser`). When
  checking "is this the store admin" for D-10/D-14 (admin can see Todos read-lists / archive
  others' Todos), do not just check `user.roles.includes('admin')` — verify against the same
  role-resolution path `FunctionPermissionService` and `UserRoleGuard` already use, or better,
  gate that ability behind its own function slug rather than a raw role string check.

## Attachments and Privacy (D-17) — Critical Finding

Verified in `api-ventago/src/common/minio/minio.controller.ts`:

```ts
// Source: api-ventago/src/common/minio/minio.controller.ts:94-111 (verified in repo)
@Public()
@Get(':filename')
async getImage(@Param('filename') filename: string, @Res() res: any) {
  if (!isPubliclyServable(filename)) {
    throw new ForbiddenException('Objeto no disponible públicamente');
  }
  // streams from MinIO with zero auth/visibility check
}
```

`isPubliclyServable()` only rejects names containing `/`, `..`, `\`, or ending in a blacklisted
extension (`.csv .xlsx .xls .pdf .txt .zip .json .doc .docx`). A flat-named `.jpg`/`.png` is
served to **anyone**, unauthenticated, forever.

**Implication for D-17 (personal-nota photo attachments must stay private per D-05):** if
`MinioService.uploadFile()` is called with a flat filename (the way `store.controller.ts` does
for logos, which are *meant* to be public), the resulting image becomes world-readable through
`/minio/:filename` regardless of whether the nota is personal. This directly violates D-05 for
attachments.

**Required approach:**
1. Upload nota attachments with a path-prefixed key, e.g. `notas/{storeId}/{notaId}/{uuid}.jpg`.
   This alone makes `isPubliclyServable()` reject it (contains `/`) — the public route 403s it.
2. PDFs are already blocked by extension regardless of path — no extra work needed there, but
   they still need an authenticated route to be *fetchable at all*.
3. Add a new endpoint (e.g. `GET /notas/attachments/:notaId/:filename`) that: (a) requires
   `@Auth()`, (b) re-runs the same visibility predicate as nota detail (sender/recipient/all),
   (c) only then streams via `MinioService.getObjectStream()`. Do **not** extend
   `MinioController` itself — it's a shared, cross-module component; visibility logic belongs in
   the Notas module.
4. This also naturally satisfies "reply attachments (1 photo)" — same path-prefix + same
   authenticated route, keyed by reply id instead of nota id.

## Realtime Integration Detail

Verified in `api-ventago/src/common/socket/websocket.gateway.ts` and `.service.ts`:

- Connection auth: browser JWT is verified in `handleConnection`; `client.data.userId`/`storeId`
  come from the verified JWT payload, never from client-sent values (`register_user` handler
  only trusts `client.data`, confirmed at `websocket.gateway.ts` `handleRegisterUser`).
- Room joins: `register_user` puts the socket in both `user:{id}` and `store:{id}` rooms
  (`websocket.service.ts registerUser`). These rooms already exist and are joined by every
  logged-in browser tab as soon as `TeamChatPanel`/any other `useRealtime('realtime', ...,
  {room: {event:'register_user', ...}})` consumer mounts — but per `socket-registry.ts`'s "leave"
  documentation, `register_user`'s room has **no leaveEvent** and is intentionally kept for the
  whole session (multiple consumers share it). This means: if the Notas toast/badge listener is
  the *only* thing that calls `register_user` room join on a given page, it still works fine
  session-wide, but the room join is idempotent/shared — no special unregister logic needed for
  it specifically.
- Emit pattern for new nota: `emitToUser(recipientId, 'nota:new', payload)` for each recipient
  when audience is a user list, or `emitToStore(storeId, 'nota:new', payload)` when audience is
  'all'. Mirrors `team-chat.service.ts:44-55` exactly.
- Emit pattern for reply (D-13, "nota 참여자 + 대상에게 알림"): iterate `nota_recipients` (or all
  store users if audience='all') and `emitToUser` each, or a single `emitToStore` when
  audience='all' (simpler, and the visibility predicate already prevents non-participants from
  seeing it if they open the app).
- Rate/volume: no rate limiting is applied to `emitToUser`/`emitToStore` themselves — the existing
  `SocketRateLimiter` only guards **connection attempts**, not emitted event volume. Not a
  concern at Notas' expected volume (small stores, human-authored notes).

## Sidebar Badge Injection — Pitfall Detail

Verified via `ventago-app/src/@core/layouts/components/vertical/navigation/VerticalNavLink.tsx:182`
and `src/navigation/vertical/index.ts`:

- `item.badgeContent` is rendered as a MUI `Chip` if truthy — the render code already exists and
  is dead code today (`grep badgeContent` across the repo shows only the type definition and this
  render call; **zero producers**). This confirms CONTEXT's note "아직 채우는 곳 없음".
- The nav item array is built by `useNavigation()` (`src/navigation/vertical/index.ts`), memoized
  with `useMemo(..., [user?.structure, user?.roles, t])`. It is called directly as
  `VerticalNavItems()` inside `UserLayout.tsx:172` (`const memoizedNavItems = VerticalNavItems()`)
  and passed down as `verticalLayoutProps.navMenu.navItems` → `VerticalLayout.tsx:112` →
  `Navigation` (wrapped in `memo()` at the bottom of
  `src/@core/layouts/components/vertical/navigation/index.tsx`).
- **Pitfall:** adding unread-count as a new `useMemo` dependency (needed to compute
  `badgeContent` for the Notas item) means `memoizedNavItems` gets a **new array reference**
  every time the unread count changes. Because `Navigation` is `memo()`-wrapped and receives this
  array as the `verticalNavItems` prop, a shallow prop-equality check will fail on every unread
  change, forcing a re-render of the whole nav tree — precisely the class of problem CLAUDE.md's
  "사이드바 리렌더링 방지" section exists to prevent.
- **Recommended mitigation for the plan:** unread-count changes are infrequent (a new nota
  arriving, or opening/closing the Notas page), unlike the earlier BranchContext problem (which
  re-rendered on every branch-selector interaction). Document this as an accepted, bounded
  re-render (occurs only on new-nota events, not on every render), but the planner should NOT
  add unread count as a dependency of an *unrelated*, frequently-changing piece of state, and
  should keep the count itself in a small, dedicated store (context or SWR cache) rather than
  bloating `useAuth()`'s `user` object (which many other memoized trees depend on).

## Common Pitfalls

### Pitfall 1: Treating `TenantGuard` as sufficient for D-05
**What goes wrong:** A store admin's "view all notes" screen silently includes other users'
personal notes.
**Why it happens:** The tenant hook only filters by `store_id`; it has no per-row ACL.
**How to avoid:** Every Notas service query method must apply the explicit sender/recipient/all
predicate documented above, including search (D-18 explicitly calls this out).
**Warning signs:** A code review or manual test where user B can open a nota addressed to user A
only, by ID or by list, while impersonating a store admin.

### Pitfall 2: Serving private attachments through the public MinIO route
**What goes wrong:** A personal nota's photo attachment becomes accessible to anyone with the URL.
**Why it happens:** `MinioService.uploadFile()` defaults to a flat filename; the shared
`/minio/:filename` route is `@Public()` with only a filename-shape check, no visibility check.
**How to avoid:** Always upload nota attachments with a `/`-containing key and serve them only
through a new authenticated, visibility-checked Notas endpoint.
**Warning signs:** Attachment `src` URLs in the frontend pointing at `/api/minio/...` instead of
a Notas-specific route.

### Pitfall 3: Seed migration ordering / deploy sequencing
**What goes wrong:** `FunctionGuard` denies any slug not yet in the `functions` table
(Phase 93 P1-e behavior, confirmed in `function-guard.decorator.ts` comments). If code
referencing `notas-enviar-todos` or `ver-notas` deploys before the seed SQL runs on prod, every
request is denied for everyone.
**Why it happens:** Deploy and migration are two separate steps (Jenkins build vs. manual SSH
`psql` apply per CLAUDE.md's migration rules).
**How to avoid:** Apply the seed SQL to both local (5432) and prod (5434) **before** pushing the
code that uses the new slugs, exactly as CLAUDE.md's "DB 마이그레이션 적용 규칙" and the
`2026-09-24-phase93-p5-seed-herramientas.sql` comment header mandate.
**Warning signs:** 403s appearing for the Notas menu immediately after a deploy that "should have
worked."

### Pitfall 4: `ON CONFLICT` silently duplicating grants on second migration run
**What goes wrong:** Re-running the seed migration (e.g. during a failed-deploy retry) duplicates
`role_functions` rows for the 4 global roles (`vendedor`/`admin`/`superadmin`/`gerente`, which
have `store_id IS NULL`).
**Why it happens:** Postgres treats `NULL <> NULL` for unique-constraint purposes, so
`ON CONFLICT (role_id, function_id, store_id)` never fires for those rows.
**How to avoid:** Use `NOT EXISTS (... store_id IS NOT DISTINCT FROM ...)` guards, as
`2026-09-24-phase93-p5-seed-herramientas.sql` does. Add a verification `DO $$ ... RAISE
EXCEPTION` block like that migration's step 6, so a bad second run fails loudly instead of
silently duplicating or (worse) restoring a permission an admin deliberately revoked.

### Pitfall 5: New-hire unread computation (D-07) computed client-side or naively
**What goes wrong:** A newly hired user sees hundreds of historic Todos notes marked unread, or
(inverse bug) never sees the mandatory pinned notes as unread.
**Why it happens:** "Unread" for Todos notes must be defined relative to `users.created_at` +
pinned-status, not just "no NotaRead row exists" (which would be true for every historic note for
a new user).
**How to avoid:** Unread predicate for audience='all' notes: `(nota.pinned = true) OR
(nota.createdAt > user.createdAt)` AND no matching ack/read row. Confirmed `users.created_at` is
`NOT NULL` and always populated (`.planning/intel/db-schema-tables.md` line 3854) so this
comparison is always well-defined. The approved sketch encodes exactly this logic in its
`isUnread()` JS function — use it as the literal spec.
**Warning signs:** Onboarding a test "Pablo, ingresó hoy" user (as the sketch's "Ver como"
selector does) and checking their unread badge count against expectation.

### Pitfall 6: Timezone mismatch on expiry (D-16)
**What goes wrong:** A nota expires "early" or "late" relative to what the store owner expects,
mirroring the historical `daily_number`/`DEFAULT_STORE_TZ` mismatch documented in
`attendance-time.util.ts`'s own comments.
**Why it happens:** Comparing `expiresOn` (a date, no time) against `new Date()` in UTC instead
of the store's local calendar day.
**How to avoid:** Reuse `storeNowParts(store.timezone)` / build the "is expired" check the same
way `attendance-time.util.ts` computes date boundaries — do not hand-roll a new UTC offset
calculation. Use `DEFAULT_STORE_TZ` (`America/Argentina/Buenos_Aires`) as the fallback constant,
not the stale `stores.timezone` column default (`America/Bogota`), matching the documented reason
in that file.
**Warning signs:** A note set to expire "today" showing as still active (or already vencida) for
2+ hours around midnight Argentina time.

### Pitfall 7: One-level reply enforcement
**What goes wrong:** A reply-to-a-reply silently succeeds, breaking D-13's explicit
"no threading beyond one level" decision.
**Why it happens:** If `NotaReply` has a self-referential `parentReplyId`, nothing stops nesting
unless the service explicitly validates depth.
**How to avoid:** Do not add a self-referential FK to `NotaReply` at all — model replies as a flat
list keyed only by `notaId`. This makes nested replies structurally impossible rather than
merely validated against, which is more robust (mutation-testing lesson from this repo's own
history: "structurally impossible" beats "checked at write time").

### Pitfall 8: `withAccess`/role-string admin checks instead of function-slug checks
**What goes wrong:** D-10/D-14 give the store "admin" extra visibility (Todos read-lists) and
extra power (archive others' Todos). If this is implemented as a raw `user.roles.includes('admin')`
check, it inherits the repo's documented pitfall that `req.user.roles` is not always filtered by
the active store.
**How to avoid:** Prefer gating "admin-level Notas power" behind its own function/action (e.g., an
`update` action on `notas-enviar-todos`, or a dedicated `notas-moderar` slug) resolved through
`FunctionPermissionService`, the same path every other permission check in the repo uses, rather
than inventing a second, parallel "is admin" test.

## Code Examples

### Team-chat model, as the closest structural precedent
```ts
// Source: api-ventago/src/app/team-chat/team-message.model.ts (verified in repo)
@Table({ timestamps: true, tableName: 'team_messages' })
export class TeamMessage extends Model {
  @ForeignKey(() => Store)
  @Column({ type: DataType.INTEGER, allowNull: false })
  storeId: number;

  @ForeignKey(() => Users)
  @Column({ type: DataType.INTEGER, allowNull: false })
  senderId: number;

  // null = store-wide (Todos pattern) — Notas' `audience`/`nota_recipients` design
  // generalizes this same idea to multi-recipient instead of a single nullable receiverId.
  @Column({ type: DataType.INTEGER, allowNull: true })
  receiverId: number;
}
```

### Realtime emit, exact pattern to copy
```ts
// Source: api-ventago/src/app/team-chat/team-chat.service.ts:44-55 (verified in repo)
if (receiverId) {
  this.wsService.emitToUser(receiverId, 'team:message', payload);
  this.wsService.emitToUser(senderId, 'team:message', payload);
} else {
  this.wsService.emitToStore(storeId, 'team:message', payload);
}
```

### Test harness for a service with a Sequelize model + a connection dependency
```ts
// Source: api-ventago/src/app/expense-categories/expense-category.service.spec.ts:36-70 (verified)
const moduleRef = await Test.createTestingModule({
  providers: [
    NotasService,
    { provide: getModelToken(Nota), useValue: mockNotaModel },
    { provide: getConnectionToken(), useValue: mockSequelize },
    { provide: WebsocketService, useValue: { emitToUser: jest.fn(), emitToStore: jest.fn() } },
  ],
}).compile();
svc = moduleRef.get(NotasService);
```
Do not `new NotasService(...)` manually — per repo convention/memory, services depending on
injected models must go through `Test.createTestingModule`, or constructor wiring subtleties
(decorator metadata, DI tokens) are silently skipped.

### Store-local date helper, reuse instead of hand-rolling
```ts
// Source: api-ventago/src/app/attendance/attendance-time.util.ts (verified in repo)
import { storeNowParts, nextMidnightISO } from 'src/app/attendance/attendance-time.util';
// storeNowParts(store.timezone) -> { date: 'YYYY-MM-DD', time: 'HH:mm:ss' }
// nextMidnightISO(store.timezone) -> ISO string of the next store-local midnight
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Team-chat's aspirational `team_message_reads` table (referenced in a comment only) | Notas must build a real `nota_reads` table from day one | N/A (Notas is new) | Do not treat team-chat's group-read comment as a working precedent — verified the table does not exist in `migrations/` or `src/app/team-chat/` |
| Direct `socket.io-client` imports per component | Single shared socket per namespace via `src/realtime/socket-registry.ts` | Phase 85 W2 (2026-08-20) | Notas realtime code must go through `useRealtime()`, never call `io()` directly (ESLint-enforced) |
| Menu items hardcoded as literal JSX in `vertical/index.ts` | Menu items derived from DB `modules`/`functions` seed + `role_functions` grants | Phase 57 / Phase 93 | The Notas menu entry is a seed-migration concern, not a frontend code change alone |

**Deprecated/outdated:** none directly relevant; this is a greenfield module.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The Notas module's top-level nav `app` should be a new dedicated app (or an app universal to all roles), not `herramientas` (which is deliberately non-billed/auxiliary and excluded from the main menu group) | Pattern 2 | If planner instead hangs Notas off `herramientas`, it renders as an auxiliary/tools-section item rather than a main sidebar entry, which may not match user expectation of "사이드바 「Notas」 메뉴" as a first-class item like in the sketch (`.side .it` list, same level as Ventas/Productos/Caja) |
| A2 | `role_functions.store_id` semantics for a brand-new module: whether Notas' function grants should be seeded per-store (like `2026-09-27-e-modulo-impresoras.sql`, which copies `rf.store_id` from an existing grant) or as global roles (`store_id IS NULL`, like the `2026-09-24` Herramientas seed for global-role grants) | Pattern 2 | Wrong choice could either fail to grant Notas to some stores' custom roles, or grant it to roles that shouldn't have it — needs a pre-migration query of `SELECT DISTINCT store_id FROM roles` to decide, same diligence the two precedent migrations show |
| A3 | Attachment count/size validation (max 5 photos+PDF per nota, 1 photo per reply) is assumed to be enforced only at the API layer (DTO/service), with no separate DB constraint — consistent with how other upload limits in the repo (`store.controller.ts`, `onboarding.controller.ts`) are enforced purely in `FileInterceptor` options, not DB constraints | §Attachments and Privacy | If wrong, a client bypassing the app's compose dialog (calling the API directly) could exceed 5 attachments; low risk given internal-tool nature of this feature, but planner should decide if a DB-level check is warranted |

**If this table is empty:** N/A — see rows above.

## Open Questions (RESOLVED — see CONTEXT.md D-20/D-21)

> RESOLVED: OQ1 → D-20 (herramientas app, auxiliary). OQ2 → D-21 (copy `ver-chat-de-equipo` grants). OQ3 → reuse `notas-enviar-todos` / `create` (plans 96-01/05/06).

1. **Which `app_id` should the `notas` module belong to for the sidebar seed?**
   - What we know: precedent migrations attach new modules to `admin` (impresoras) or a new
     dedicated `herramientas` app (auxiliary tools). Neither fits a main, everyday, all-roles
     feature exactly.
   - What's unclear: whether an existing "universal" app exists that every store/role already has
     (the Herramientas seed migration's own audit found no app is universal — coverage ranges
     from 73/120 to 93/120 roles depending on app).
   - Recommendation: the planner's Wave 0 should run `SELECT a.slug, count(DISTINCT sa.store_id)
     FROM apps a JOIN store_apps sa ON sa.app_id=a.id AND sa.enabled GROUP BY a.slug` and
     `SELECT a.slug, count(*) FROM role_functions rf JOIN functions f ON f.id=rf.function_id JOIN
     modules m ON m.id=f.module_id JOIN apps a ON a.id=m.app_id GROUP BY a.slug` (adapted) to
     decide between "new dedicated `notas` app, seeded into every store's `store_apps` like
     `herramientas` was" (safest, mirrors precedent exactly) vs. reusing an existing app. Given
     the strong precedent and the fact Notas has zero billing implications, a **new dedicated
     app** (non-auxiliary, its own sidebar group) is the safer default recommended here, but
     needs user/planner confirmation since it changes menu grouping shown in the sketch (single
     `<div class="it">` at top level, not a group).

2. **What real user/role set exists per store today, for choosing global vs. per-store
   `role_functions` seeding?**
   - What we know: 4 global roles exist (`vendedor`, `admin`, `superadmin`, `gerente`, ids 1-4,
     `store_id IS NULL`); individual stores can also have custom per-store roles.
   - What's unclear: whether granting `ver-notas` to the 4 global roles is sufficient for all
     stores, or whether some stores have custom roles that also need the grant (as
     `2026-09-27-e-modulo-impresoras.sql` does by copying grants from an existing function's
     `role_functions` rows rather than assuming global-only).
   - Recommendation: mirror `2026-09-27-e-modulo-impresoras.sql`'s approach — derive `ver-notas`
     grants from whichever function already represents "can see the main app" for that store's
     roles (e.g., copy from an existing near-universal function's `role_functions`), rather than
     only inserting the 4 global rows.

3. **Exact wording/slug list for the "admin can archive/see-reads for Todos" power (D-10/D-14).**
   - What we know: CONTEXT leaves permission slug naming to Claude's discretion.
   - What's unclear: whether this should be a new action (`update`/`delete`) on the existing
     `notas-enviar-todos` slug, or a distinct slug like `notas-moderar`.
   - Recommendation: reuse `notas-enviar-todos` with `update` action for pin/archive-others'-Todos
     and reserve a new slug only if a future phase needs finer separation — avoids an unnecessary
     seed-migration proliferation for a single phase.

## Environment Availability

No new external dependencies. This phase only uses already-installed and already-configured
infrastructure (PostgreSQL, MinIO, the `/realtime` Socket.IO namespace, the existing Nest/Next
toolchains). Skipping the full audit table as it would be a copy of infrastructure already
verified working by every other module in this codebase.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (api) | Jest (ts-jest), NestJS `Test.createTestingModule` harness |
| Framework (app) | Jest, but **cannot import `.tsx`** — pure logic must live in `.ts` files (per repo memory: `app-jest-cannot-import-tsx`) |
| Config file (api) | `api-ventago/jest.config.js` (existing, no changes needed) |
| Config file (app) | `ventago-app/jest.config.js` (existing) |
| Quick run command (api, scoped) | `cd api-ventago && npx jest src/app/notas --maxWorkers=1` |
| Quick run command (app, scoped) | `cd ventago-app && npx jest src/__tests__/notas --maxWorkers=1` (or wherever pure-logic specs land) |
| Full suite command | **Do not run full jest** per operating constraints of this environment; full-suite execution is a CI/human concern, not this research's or the planner's execution step. When it must run: `--maxWorkers=1` always (memory: 2 workers kill random suites via SIGTERM). |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-05 | Personal nota invisible to admin, service-level filter | unit | `npx jest src/app/notas/notas.service.spec.ts -t "visibility" --maxWorkers=1` | ❌ Wave 0 |
| D-07 | New-hire unread excludes pre-hire non-pinned Todos | unit | `npx jest src/app/notas/notas.service.spec.ts -t "unread" --maxWorkers=1` | ❌ Wave 0 |
| D-11 | Normal=seen-on-open, Importante/Urgente=ack-required | unit | `npx jest src/app/notas/notas.service.spec.ts -t "ack" --maxWorkers=1` | ❌ Wave 0 |
| D-13 | Reply nesting structurally impossible (no self-FK) | unit (schema-shape) | `npx jest src/app/notas/models/nota-reply.model.spec.ts --maxWorkers=1` | ❌ Wave 0 |
| D-16 | Expiry evaluated in store timezone, not UTC | unit | `npx jest src/app/notas/notas.service.spec.ts -t "expiry" --maxWorkers=1` | ❌ Wave 0 |
| D-17 | Attachment key is path-prefixed (rejected by public `/minio/:filename`) | unit | `npx jest src/common/minio/minio.controller.spec.ts -t "isPubliclyServable" --maxWorkers=1` (extend or add) | ❌ Wave 0 (extend existing controller if a spec exists, else new) |
| menu pairing | New `#`-action menu items (if any used) have a listener | source-grep (repo convention) | `npx jest src/__tests__/menu-chat-entradas.spec.ts --maxWorkers=1` (extend, don't duplicate, if Notas adds any `#` actions) | ✅ exists, extend only if applicable — Notas likely uses a real route (`/notas`), not a `#` action, so this may not apply |
| perm seed | Seed migration idempotency / no over-grant on 2nd run | manual (SQL DO block RAISE EXCEPTION, verified by running twice locally) | `psql -p 5432 -d ventago -f api-ventago/migrations/<notas-seed>.sql` (run twice) | N/A — enforced by the migration file itself, not a jest test |
| migration conventions | New tables get owner DO block, lock_timeout, `w4-exempt`/`perm-cache` comments where applicable | automated | `npx jest src/common/migrations/migration-conventions.spec.ts --maxWorkers=1` | ✅ exists — applies automatically to any new `.sql` file dated after 2026-08-21 |

### Sampling Rate
- **Per task commit:** run the scoped `notas` directory jest command (api and/or app, whichever
  was touched), `--maxWorkers=1`.
- **Per wave merge:** same scoped commands plus `migration-conventions.spec.ts` if any migration
  file was added/changed.
- **Phase gate:** before `/gsd-verify-work`, at minimum run the scoped Notas specs plus
  `migration-conventions.spec.ts` plus (if any `#`-action menu items were added)
  `menu-chat-entradas.spec.ts`'s general "every `#` action has a listener" check. Do not run the
  full jest suite in this environment (operating constraint).

### Wave 0 Gaps
- [ ] `api-ventago/src/app/notas/notas.service.spec.ts` — covers D-05, D-07, D-11, D-16 visibility
      and unread/ack/expiry logic (mock-model harness, no DB)
- [ ] `api-ventago/src/app/notas/models/nota-reply.model.spec.ts` (or fold into service spec) —
      asserts no self-referential FK / no nested-parent acceptance path exists for D-13
- [ ] Extend or create `api-ventago/src/common/minio/minio.controller.spec.ts` — control-group
      test proving a path-prefixed key (`notas/1/2/x.jpg`) is rejected by `isPubliclyServable`,
      alongside a positive control (a flat `store_logo_x.png`-style name that legitimately should
      pass) so the test can't pass by accident
- [ ] Notas seed migration SQL — no jest gap, but needs a manual "run twice locally" check before
      first prod apply (per Pitfall 4)
- [ ] Frontend: if any pure visibility/unread logic is extracted into `.ts` (not `.tsx`) helpers
      for testability (recommended, since `app` jest cannot import `.tsx`), add
      `ventago-app/src/__tests__/notas-unread.spec.ts` or similar for the D-07 client-side badge
      count derivation, mirroring the sketch's own `isUnread()`/`unreadCount()` functions

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes (inherited) | `@Auth()` / JWT — no new auth mechanism introduced |
| V3 Session Management | yes (inherited) | Existing session/sessionToken system, unchanged by this phase |
| V4 Access Control | **yes — core of this phase** | `FunctionGuard('notas-enviar-todos', 'create')` for send-to-all; custom service-level visibility predicate (Op.or sender/recipient/all) for D-05, since no existing control covers per-row recipient ACL |
| V5 Input Validation | yes | Nest DTO validation (class-validator) on title(required)/body/importance enum/recipient id list; sanitize/validate attachment MIME type before `MinioService.uploadFile` |
| V6 Cryptography | no | No new crypto surface introduced |
| V9 Communications | yes (inherited) | Realtime traffic rides the existing authenticated `/realtime` namespace (JWT-verified handshake); no new transport |
| V12 File/Resource | **yes — core of this phase** | Attachment storage must use path-prefixed MinIO keys + a new authenticated streaming endpoint; do not reuse the public `/minio/:filename` route for anything not meant to be world-readable |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| IDOR on nota detail/attachment endpoints (guessable sequential `id`) | Information Disclosure | Visibility predicate re-checked on every read, not just list; attachment endpoint re-checks visibility per request, not cached from an earlier list call |
| Privilege escalation via role-string check instead of function-slug check for admin powers (D-10/D-14) | Elevation of Privilege | Gate admin-only Notas actions through `FunctionPermissionService`/`FunctionGuard`, not a raw `user.roles.includes('admin')` check (see Pitfall 8) |
| Public file exposure via predictable/flat MinIO keys | Information Disclosure | Path-prefixed keys + authenticated streaming route (see §Attachments and Privacy) |
| Cross-store leak via a missed `storeId` column on a new Nota* model | Information Disclosure | Every new model must include `storeId`; the `tenant-guard-coverage.spec.ts` pattern in `src/app/role/role-function/` suggests the repo already has a coverage-audit test style the planner could optionally extend to assert all new `Nota*` models are covered by `TenantGuard` (`resolveModelPolicy().guarded === true`) |
| Permission-seed replay re-granting a revoked permission | Elevation of Privilege (via careless ops) | Idempotent seed with a `RAISE EXCEPTION` guard against second-run over-grant, per Pitfall 4 |

## Sources

### Primary (HIGH confidence — verified by direct file read in this repo)
- `api-ventago/src/app/team-chat/team-message.model.ts`, `team-chat.service.ts`,
  `team-chat.controller.ts`, `team-chat.module.ts` — closest structural precedent
- `api-ventago/src/common/tenant/tenant-hooks.ts`, `tenant-scope.registry.ts` — tenant isolation
  mechanism and its explicit scope boundaries
- `api-ventago/src/common/socket/websocket.gateway.ts`, `websocket.service.ts` — realtime auth
  and room/emit API
- `api-ventago/src/common/minio/minio.controller.ts`, `minio.service.ts` — public serving
  behavior and its exact filter logic
- `api-ventago/src/app/auth/decorators/function-guard.decorator.ts`,
  `src/app/auth/guards/function-permission.guard.ts`,
  `src/app/auth/decorators/get-user.decorator.ts` — permission/auth composition
- `api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql`,
  `2026-09-24-phase93-p5-seed-herramientas.sql`, `store-notices.sql`, `vendedor-devices.sql` —
  seed/DDL migration conventions (owner DO block, idempotency, verification blocks)
- `api-ventago/src/common/migrations/migration-conventions.spec.ts` — enforced migration rules
  and cutoff date
- `api-ventago/src/app/attendance/attendance-time.util.ts`, `src/common/constants/timezone.ts` —
  store-timezone helpers
- `api-ventago/src/common/pagination/pagination.util.ts` — `clampPageSize`
- `api-ventago/src/app/expense-categories/expense-category.service.spec.ts` — jest harness
  pattern (`Test.createTestingModule` + `getModelToken`/`getConnectionToken`)
- `.planning/intel/db-schema-tables.md` (lines 3171-3208, 3838-3863) — `stores`/`users` columns
  (`stores.timezone` default, `users.created_at` NOT NULL)
- `ventago-app/src/realtime/socket-registry.ts`,
  `ventago-app/src/components/team-chat/TeamChatBubble.tsx`,
  `ventago-app/src/components/team-chat/TeamChatPanel.tsx` — frontend realtime pattern and its
  polling-vs-listener distinction
- `ventago-app/src/navigation/vertical/index.ts`,
  `ventago-app/src/@core/layouts/components/vertical/navigation/VerticalNavLink.tsx`,
  `ventago-app/src/@core/layouts/components/vertical/navigation/index.tsx`,
  `ventago-app/src/layouts/UserLayout.tsx`, `ventago-app/src/@core/layouts/VerticalLayout.tsx` —
  sidebar/badge data flow and memoization boundaries
- `ventago-app/src/configs/withAccess.tsx` — admin bypass semantics for page-level gating
  (confirms it is not a security boundary)
- `ventago-app/src/__tests__/menu-chat-entradas.spec.ts` — repo's existing convention for testing
  "every `#` menu action has a listener" and multi-source menu registries
- `.planning/sketches/notas-compartidas.html` — the approved UI contract (D-02, D-19); its inline
  JS (`isUnread`, `visible`, `recips`, `needAck`, `list`) is the literal reference implementation
  for the visibility/unread/sort rules and should be read directly by the planner, not
  re-derived from prose

### Secondary (MEDIUM confidence)
- None — no WebSearch was needed; this phase is entirely internal-reuse and repo-composition, not
  a new external library or public API integration.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; all reuse verified by direct grep/read of installed code
- Architecture: HIGH — module shape, tenant hook behavior, realtime API, and MinIO public-serving
  logic all confirmed by reading the actual source, not inferred
- Pitfalls: HIGH — each pitfall is backed by a specific file/line finding (tenant hook scope,
  MinIO public route logic, seed migration NULL-conflict behavior, badge memoization chain),
  not generic best-practice speculation
- Open questions (A1/A2/OQ1/OQ2): MEDIUM — these require a data query the planner/Wave 0 should
  run against the live schema (role/app coverage per store) that this research pass did not run
  against production data; flagged explicitly rather than guessed

**Research date:** 2026-09-28
**Valid until:** ~30 days (stable internal architecture; re-verify if Phase 93-style permission
refactors or tenant-guard changes land before planning begins)
