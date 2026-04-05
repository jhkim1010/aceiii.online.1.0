# Phase 1: UI 토글 메커니즘 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-05
**Phase:** 01-ui-ux
**Areas discussed:** 토글 저장소, Phase 구조, 토글 범위, 권한, 스위치 UI, 요구사항 이동

---

## 초기 요청 (Phase 재구성)

유저가 기존 Phase 1 (UI/UX 개선) 대신 토글 기반 점진적 UI 전환 방식을 제안.

**User's choice:** 사이드바 하단에 "UI/UX nuevo" 체크박스 추가. 활성화한 유저에게만 새 UI 표시, 비활성화 유저에게는 기존 UI 유지.

---

## 토글 저장소

| Option | Description | Selected |
|--------|-------------|----------|
| DB (user 테이블) | 유저별 설정, 어느 디바이스에서든 유지. users 테이블에 ui_mode 컬럼 추가 | ✓ |
| localStorage | 간단하지만 브라우저/디바이스별로 다름 | |
| Store 설정 (store 테이블) | 매장 단위로 전체 유저에게 적용 | |

**User's choice:** DB (user 테이블)
**Notes:** 유저별 개인 설정으로 디바이스 무관하게 유지

---

## Phase 구조

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 1 = 토글 기반 + 새 UI | Phase 1에 토글 메커니즘 + 새 UI 디자인 모두 포함 | |
| Phase 0.5 = 토글, Phase 1 = 새 UI | 토글 메커니즘을 별도 phase로 분리 | |
| Phase 1에 토글만, Phase 4로 새 UI | Phase 1 = 토글 메커니즘, Phase 4 = 새 UI 디자인 | ✓ |

**User's choice:** Phase 1에 토글만, Phase 4로 새 UI
**Notes:** 토글 인프라를 먼저 구축하고, 새 UI 디자인은 마지막 Phase로

---

## 토글 적용 범위

| Option | Description | Selected |
|--------|-------------|----------|
| 전체 페이지 | 로그인, 대시보드, 사이드바, 모든 페이지에 새 UI 적용 | |
| 로그인 + 대시보드만 | UX-01, UX-02만 토글 대상 | |
| 페이지별 점진적 적용 | 토글 ON이더라도 새 UI가 준비된 페이지만 변경 | ✓ |

**User's choice:** 페이지별 점진적 적용
**Notes:** 새 UI가 준비된 페이지만 전환, 미준비 페이지는 기존 유지

---

## 토글 접근 권한

| Option | Description | Selected |
|--------|-------------|----------|
| 모든 유저 | 누구나 사이드바에서 토글 가능 | |
| admin/superadmin만 | 관리자만 토글 볼 수 있음 | ✓ |
| store 단위 설정 | 매장 소유자가 활성화하면 해당 매장 전체 적용 | |

**User's choice:** admin/superadmin만
**Notes:** 일반 vendedor/gerente에게는 체크박스 자체가 숨겨짐

---

## 스위치 UI 디자인

| Option | Description | Selected |
|--------|-------------|----------|
| MUI Switch + 라벨 | 사이드바 하단에 작은 Switch 컴포넌트 + 'Nuevo UI' 라벨 | |
| 체크박스 + 라벨 | 기존 체크박스 스타일로 간단하게 | ✓ |
| Chip 토글 | 'BETA' 칩을 클릭하면 토글 | |

**User's choice:** 체크박스 + 라벨

---

## 요구사항 이동

| Option | Description | Selected |
|--------|-------------|----------|
| UX-01~03 모두 Phase 4로 이동 | Phase 1은 토글 인프라만 | ✓ |
| UX-01만 Phase 1에 유지 | 로그인 화면 세련화는 토글 없이도 적용 | |

**User's choice:** UX-01~03 모두 Phase 4로 이동

---

## Claude's Discretion

- 조건부 렌더링 아키텍처 패턴 선택
- DB 마이그레이션 방식
- API 엔드포인트 설계

## Deferred Ideas

- UX-01 (로그인 세련화), UX-02 (대시보드), UX-03 (UI 일관성) → Phase 4
