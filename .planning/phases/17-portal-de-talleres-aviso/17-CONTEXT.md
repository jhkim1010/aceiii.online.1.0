# Phase 17: Portal de Talleres — Context

**Gathered:** 2026-04-13
**Status:** Ready for planning
**Mode:** New feature — Flutter 독립 앱

<domain>
## Phase Boundary

외주업체(talleres/vendors)가 자체적으로 접속하여 자기에게 발송된 물건의 진행현황 확인, 수령 완료 마킹, 알림 수신, 정산 이력 확인을 할 수 있는 **Flutter 독립 모바일 앱**. 한 업체가 여러 매장(store)의 물건을 처리하는 경우도 매장별 탭으로 한눈에 관리. Ventago 본체와 완전히 분리된 앱으로 업체가 다른 매장 데이터에 접근 불가.

</domain>

<decisions>
## Implementation Decisions

### 앱 형태
- **D-01:** Flutter 독립 앱으로 구현 — Ventago 본체와 완전 분리. 별도 패키지/저장소(또는 모노레포 내 새 디렉토리)
- **D-02:** 업체가 다른 매장의 데이터에 접근 불가 — vendor 기반 인증으로 자기 데이터만 조회

### 인증
- **D-03:** 전화번호 + 4자리 PIN 로그인. 매장 관리자가 Ventago에서 vendor 등록 시 PIN 발급
- **D-04:** 백엔드에 vendor 전용 인증 엔드포인트 추가 — JWT 토큰 발급, vendor 정보 + 연결된 store 목록 반환

### 멀티매장 처리
- **D-05:** 하단 탭으로 매장 전환 — 각 매장의 발송/수령/정산이 독립 표시
- **D-06:** 로그인 후 연결된 store 목록 표시, 탭으로 자유 전환

### 기능 범위
- **D-07:** 진행현황 확인 — 내게 발송된 로트/공정 목록 + 수량 + 납기 확인 (읽기 전용)
- **D-08:** 수령 확인 — 업체가 직접 완료/부분완료 마킹 → 매장 측에 수령 알림 전송
- **D-09:** 알림 수신 — 앱 내 알림만 (푸시 없음). 새 발송, 납기 임박, 정산 완료 등
- **D-10:** 정산 이력 확인 — 나의 정산 금액/상태 확인 (수정 불가, 읽기 전용)

### 알림 시스템
- **D-11:** 앱 내 알림 목록 + 미읽음 배지 카운트. 푸시 알림 없음 (Phase 범위 외)
- **D-12:** 알림 생성은 백엔드에서 envio 생성/납기 임박 cron/정산 완료 시 자동 생성

### Claude's Discretion
- Flutter 프로젝트 구조 (디렉토리, 상태관리)
- UI 디자인 (색상, 레이아웃 — Phase 16 스타일 참고)
- 백엔드 vendor auth 엔드포인트 세부 구현
- 알림 DB 테이블 구조
- PIN 암호화/저장 방식

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 16 (의존성)
- `.planning/phases/16-control-de-talleres/16-CONTEXT.md` — Talleres UI 결정사항
- `ventago-app/src/views/talleres/components/constants.ts` — 색상, 상태 맵 상수

### 백엔드 모델 (API 확장 대상)
- `api-ventago/src/app/subcon/vendors/vendor.model.ts` — Vendor 모델 (phone, isActive)
- `api-ventago/src/app/subcon/envios/envio.model.ts` — Envio 모델 + 상태
- `api-ventago/src/app/subcon/recepciones/recepcion.model.ts` — Recepcion 모델
- `api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.model.ts` — Settlement 모델
- `api-ventago/src/app/subcon/etapas/etapa.model.ts` — Etapa 모델
- `api-ventago/src/app/subcon/lotes/lote.model.ts` — Lote 모델
- `api-ventago/src/app/subcon/vendor-etapas/vendor-etapa.model.ts` — Vendor-Etapa 단가

### 인증 시스템
- `api-ventago/src/app/auth/auth.service.ts` — 기존 JWT 인증 패턴 참조
- `api-ventago/src/app/session/` — 세션 보안 시스템 참조

### 프로젝트 컨벤션
- `.planning/codebase/CONVENTIONS.md` — 코딩 컨벤션
- `CLAUDE.md` — 프로젝트 전체 규칙

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Vendor 모델에 이미 phone 필드 존재 — PIN 컬럼 추가만 필요
- Subcon 모듈의 기존 API (envios, recepciones, settlements) — vendor 필터링 추가로 재사용 가능
- `api-ventago/src/app/subcon/subcon.module.ts` — 12개 controller/service 이미 구축

### Established Patterns
- NestJS JWT 인증 패턴 (auth.service.ts)
- Sequelize 모델 + 서비스 패턴
- Flutter 프로젝트는 아직 없음 — 새로 구축

### Integration Points
- Vendor 테이블에 PIN 컬럼 추가 (DB 마이그레이션)
- vendor_notifications 테이블 신규 생성
- 백엔드에 /vendor-portal/ 네임스페이스 API 추가
- Flutter 앱은 api-ventago 백엔드와 REST API로 통신

</code_context>

<specifics>
## Specific Ideas

- Flutter 앱은 Riverpod 상태관리 사용 (CLAUDE.md 글로벌 설정)
- 하단 탭바로 매장 전환 — 매장 로고/이름 표시
- 수령 확인 시 수량 입력 + 불량 수량 입력 가능
- 알림은 최신순 목록, 읽음/미읽음 구분
- 정산 이력은 기간 필터 + 금액 합계

</specifics>

<deferred>
## Deferred Ideas

- 푸시 알림 (Firebase Cloud Messaging) — 별도 phase
- 채팅/메시지 기능 — 매장-업체 간 커뮤니케이션
- 사진 첨부 (작업 완료 사진 업로드)
- 오프라인 모드

</deferred>

---

*Phase: 17-portal-de-talleres-aviso*
*Context gathered: 2026-04-13*
