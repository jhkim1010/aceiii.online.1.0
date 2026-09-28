# Phase 96: Notas compartidas del local - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning

<domain>
## Phase Boundary

사이드바 「Notas」 메뉴. 한 매장 안에서 사용자가 **매장 전체(Todos)** 또는 **한 명 이상 선택한 사용자**에게
중요한 nota 를 기록·전송하고, 언제든 지난 nota 를 조회·검색하며, 반응(reacción)·답글(respuesta)을 단다.
매장(`store_id`) 단위 격리는 절대 규칙이다.

범위 밖: 매장 간 전달, 슈퍼관리자 공지(Store Notices 가 이미 담당), 실시간 대화(Team Chat 이 담당).

</domain>

<decisions>
## Implementation Decisions

### Team Chat 과의 관계
- **D-01:** Notas 는 Team Chat 과 **별개 기능**이다. 채팅 = 흘러가는 대화, nota = 남는 기록.
  테이블·화면은 새로 만들고, `/realtime` 소켓(`emitToUser`/`emitToStore`)과 매장 사용자 목록만 재사용한다.
  Team Chat(`team_messages`, `TeamChatBubble`)은 **건드리지 않는다.**
- **D-02:** 화면 형태 = **B · 받은편지함형 2칸**(2026-09-28 목업 비교 후 사용자 선택).
  왼쪽 목록(보낸이 → 대상 · 시각 · 제목 · 본문 한 줄, 고정·안읽음 점·중요도 색 띠), 오른쪽 선택한 nota 본문 +
  Entendido 게이트 · 반응 · 읽음 목록 · 답글 스레드. 좁은 화면에서는 목록 아래로 본문이 쌓인다.
  기준 목업: `.planning/sketches/notas-compartidas.html` (「B · Bandeja」). A(카드)는 채택하지 않음.

### 대상과 작성 권한
- **D-03:** 「Todos」 발송은 **권한(function)으로 제어**한다(예: slug `notas-enviar-todos`). 기본값은 admin 역할만 부여.
  개인·일부 대상 발송은 Notas 메뉴에 접근할 수 있는 사용자 누구나 가능.
- **D-04:** 대상은 **Todos 또는 1명 이상 선택한 사용자**. 1명이면 개인 nota. 지점 단위 발송은 없음.
- **D-05:** 개인·일부 대상 nota 는 **보낸 사람과 받는 사람만** 본다. 매장 admin 도 볼 수 없다
  (서버가 조회 시 거른다 — 프론트 숨김이 아니라 API 가 거절).
- **D-06:** nota 형식 = **제목(필수) + 본문 + 중요도**(`Normal` / `Importante` / `Urgente`). 카테고리 없음.
- **D-07:** 「Todos」 = 매장의 공용 기록. **나중에 입사한 사용자도 과거 Todos nota 를 본다.**
  단, 신입에게 과거 nota 가 전부 「안읽음」으로 쌓이지 않게 한다 — 신입의 안읽음 대상은 **고정(Fijada) nota 와 입사 이후 nota** 뿐.

### 읽음 확인과 알림
- **D-08:** 새 nota 알림 = 사이드바 「Notas」 옆 **안읽음 개수 배지** + 소켓 **실시간 토스트**(클릭하면 해당 nota 열림).
- **D-09:** POS(`nueva-venta`) 화면에서는 **배지만**, 토스트·팝업 없음(판매 중 포커스·단축키를 빼앗지 않는다). Urgente 도 동일.
- **D-10:** 보낸 사람에게 **읽은 사람 / 안 읽은 사람 목록**(「3/7 leído」 + 이름·시각). Todos nota 는 매장 admin 도 볼 수 있다
  (개인 nota 는 D-05 에 따라 당사자만).
- **D-11:** 읽음 기준 — `Normal` 은 **본문을 열면** 읽음. `Importante`·`Urgente` 는 **「Entendido」 버튼**을 눌러야 「확인함」.
  (열람과 확인을 구분해 기록: 열람 시각 / 확인 시각)

### 반응·답글과 nota 수명
- **D-12:** 반응 = **고정 5개** 👍 ✅ 👀 ❤️ 😂. 한 사람이 여러 개 가능, 다시 누르면 취소, 호버로 누가 눌렀는지.
- **D-13:** 답글 = **한 단계 스레드**(답글의 답글 없음). nota 를 볼 수 있는 사람 전원이 답글을 본다
  (Todos → 모두, 개인 → 당사자들). 답글에도 반응 가능. 답글이 달리면 nota 참여자(작성자 + 대상)에게 알림/배지.
- **D-14:** 수정 = 가능, 「editado」 표시 + **이전 내용 이력 보존**. 삭제 = **소프트 삭제(「Archivada」)** — 목록에서 빠지고 기록은 남음.
  매장 admin 은 남의 Todos nota 도 보관 처리할 수 있다(개인 nota 는 불가 — D-05).
- **D-15:** **상단 고정(Fijar)** — Todos nota 는 D-03 의 Todos 발송 권한자가 고정. 개인 nota 는 받는 사람이 **자기 목록에서만** 고정.
- **D-16:** **만료일**(선택) — 지나면 목록·배지·고정에서 빠지고 「Vencidas」 필터로 조회. 삭제하지 않음.
  날짜 판정은 **매장 타임존** 기준(DB 는 UTC — `stores.timezone`).
- **D-17:** **첨부** = 사진 + PDF, nota 당 최대 5개(이미지는 미리보기, PDF 는 링크). 답글에는 사진 1개. MinIO 저장.
  크기 상한은 기존 업로드 상한을 따른다(nginx · 앱 상수 · multer 3층 확인).
- **D-18:** **검색** — 제목·본문으로 지난 nota 검색. 검색 결과도 D-05 가시성 규칙을 그대로 따른다.
- **D-19:** 탭 = Todas · Para mí(안읽음 개수) · Enviadas · Archivadas · Vencidas — 목업 그대로(사용자 이견 없음).
  기본 정렬: 고정 → 안읽음 → 최신.

### Claude's Discretion
- 테이블 설계(nota · 대상 · 읽음/확인 · 반응 · 답글 · 첨부 · 수정 이력), 인덱스, 페이지네이션(pageSize ≤ 50).
- 토스트 컴포넌트·배지 폴링/소켓 갱신 방식, SWR 키 설계.
- 권한 slug 이름과 시드 마이그레이션 구성(단, 사이드바는 structure 시드가 **코드보다 먼저** 나가야 한다).
- 소켓 이벤트 이름(`nota:new`, `nota:reply`, `nota:reaction` 등).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 프로젝트 규약
- `CLAUDE.md` — 멀티테넌트(store_id), 무중단 마이그레이션(W4: CONCURRENTLY·lock_timeout·NOT VALID), 새 테이블 owner coolsistema, perm-cache 주석, ESLint 규칙, 300ms/SWR/pageSize 규약, 표 밀도(`TABLE_ROW_HEIGHT`)
- `.planning/intel/db-schema-tables.md` · `.planning/intel/db-schema-fks.md` — `users`, `stores.timezone` 등 컬럼 확인
- `api-ventago/src/common/migrations/migration-conventions.spec.ts` — 마이그레이션 규약 테스트

### 화면 기준
- `.planning/sketches/notas-compartidas.html` — 채택안 B 「Bandeja」, 권한·가시성·배지 동작의 기준 시연

### 재사용할 기존 기능 (참조 구현)
- `api-ventago/src/app/team-chat/` — `team-message.model.ts`, `team-chat.service.ts`(emit L46-55, 사용자 목록 L162), `team-chat.controller.ts` — 가장 가까운 선례(Todos=receiverId NULL 패턴)
- `ventago-app/src/components/team-chat/TeamChatBubble.tsx` · `TeamChatPanel.tsx` — 안읽음 배지·소켓 구독 선례
- `api-ventago/migrations/store-notices.sql` + `admin-console.controller.ts` L153-216 + `ventago-app/src/views/components/NoticesBanner.tsx` — 읽음 처리 선례
- `api-ventago/src/common/socket/websocket.gateway.ts`(`/realtime`, register_user L227) · `websocket.service.ts`(emitToUser L79, emitToStore L86)
- `ventago-app/src/realtime/socket-registry.ts` — 프론트 소켓 연결

### 사이드바·권한
- `ventago-app/src/navigation/vertical/index.ts` · `navigation/menuRegistry.ts` — structure 기반 메뉴
- `ventago-app/src/@core/layouts/components/vertical/navigation/VerticalNavLink.tsx:182` — `badgeContent` 칩(아직 채우는 곳 없음)
- `api-ventago/migrations/2026-09-27-e-modulo-impresoras.sql` · `2026-09-24-phase93-p5-seed-herramientas.sql` — 메뉴·function·role_functions 시드 선례
- `api-ventago/src/app/auth/decorators/function-guard.decorator.ts:79` — `@FunctionGuard`
- `ventago-app/src/configs/withAccess.tsx` — ★ admin 은 전부 통과하므로 D-03/D-05 를 막는 수단이 될 수 없다

### 파일
- `api-ventago/src/common/minio/minio.service.ts:74` — `uploadFile`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `/realtime` 게이트웨이의 `user:{id}` / `store:{id}` 룸 — 새 nota·답글·반응 푸시에 그대로 사용
- `GET /team-chat/users` — 매장 활성 사용자 목록(id·name·lastName·username) → 대상 선택기
- MUI `Badge`(TeamChatBubble) 와 사이드바 `badgeContent` 칩
- `MinioService.uploadFile` / `removeFile`

### Established Patterns
- 사이드바는 `user.structure`(apps→modules→functions)에서 파생 → **시드 마이그레이션을 코드 배포보다 먼저** 운영에 적용
- 백엔드 권한은 `@FunctionGuard(slug, action)`; 프론트 `WithAccess` 는 admin 우회 — 보안 경계는 서버
- 새 페이지는 `next/dynamic(..., { ssr: false })`
- 프론트에는 매장 타임존 헬퍼가 없다 — 만료일·시각 표시는 `stores.timezone` 기준으로 새로 다뤄야 함

### Integration Points
- 사이드바 메뉴(structure 시드) · `UserLayout` 의 소켓/토스트 마운트 지점 · POS 화면에서의 토스트 억제(D-09)
- `auth/me` 의 structure/권한 응답

</code_context>

<specifics>
## Specific Ideas

- 중요한 nota 는 「읽었다」가 아니라 「이해했다(Entendido)」를 남겨야 한다 — 매장 운영 지시의 전달 확인 용도.
- 신입이 들어와도 매장 규칙(고정 nota)은 바로 보여야 한다.
- 판매 중에는 방해하지 않는다(POS 는 배지만).

</specifics>

<deferred>
## Deferred Ideas

- 지점(sucursal) 단위 발송 — 이번에는 Todos / 사용자 선택만.
- 카테고리 분류 — 이번에는 중요도만.
- 다단계 스레드 · 자유 이모지.

</deferred>

---

*Phase: 96-notas-compartidas-del-local*
*Context gathered: 2026-09-28*
