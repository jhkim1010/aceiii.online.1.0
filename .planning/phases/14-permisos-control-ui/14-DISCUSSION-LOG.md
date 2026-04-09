# Phase 14: Permisos Control — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-09
**Phase:** 14-permisos-control-ui
**Areas discussed:** 적용 범위, 접근 권한, 차단 UX, 기존 UI, Granularity

---

## 적용 범위

| Option | Description | Selected |
|--------|-------------|----------|
| UI 관리 화면만 | 백엔드 구조 유지, 관리 UI만 개선 | |
| UI + CASL 강제 적용 | 관리 UI + 프론트 CASL granular 변경 | |
| UI + CASL + 백엔드 Guard | Full stack — UI + CASL + API Guard | ✓ |

**User's choice:** UI + CASL + 백엔드 Guard
**Notes:** Full stack 적용으로 관리 UI, 프론트엔드 CASL granular enforcement, 백엔드 API Guard 모두 구현

---

## 접근 권한

| Option | Description | Selected |
|--------|-------------|----------|
| superadmin 전용 | superadmin만 권한 관리 접근 | |
| superadmin + admin | admin은 자기 매장 권한 관리 | |
| superadmin + admin + gerente | gerente도 자기 지점 유저 권한 관리 | ✓ |

**User's choice:** superadmin + admin + gerente
**Notes:** 3단계 계층적 접근

---

## 차단 UX

| Option | Description | Selected |
|--------|-------------|----------|
| 메뉴 숨김 + 401 | 사이드바 숨김, URL 직접 접근 시 401 | ✓ |
| 메뉴 비활성화(disabled) | 회색 비활성화, 클릭 시 토스트 | |
| 숨김 + 토스트 | 메뉴 숨김 + URL 접근 시 토스트 후 리다이렉트 | |

**User's choice:** 메뉴 숨김 + 401
**Notes:** 기존 AclGuard의 401 페이지 패턴과 일관됨

---

## 기존 UI 처리

| Option | Description | Selected |
|--------|-------------|----------|
| 개선 통합 | 기존 UI 개선 + /admin/permisos 통합 | |
| 새로 구축 | 별도 페이지 새로 생성 | |
| Claude 재량 | 코드베이스 분석 후 최적 접근법 결정 | ✓ |

**User's choice:** Claude 재량
**Notes:** 기존 RoleCards, UserPermissionsDrawer 등의 코드를 분석하여 최적 방식 결정

---

## 권한 Granularity

| Option | Description | Selected |
|--------|-------------|----------|
| Function 단위 유지 | 기존 ON/OFF 방식 유지 | |
| Module 단위로 단순화 | Module 단위 전체 ON/OFF | |
| CRUD Action 추가 | Function + create/read/update/delete 분리 | ✓ |

**User's choice:** CRUD Action 추가
**Notes:** 각 Function에 대해 CRUD 액션별 개별 허용/차단 가능

---

## Claude's Discretion

- 기존 UI 개선/통합 방식
- DB 스키마 변경 접근법
- 백엔드 Guard 구현 패턴
- CASL ability 빌딩 리팩토링

## Deferred Ideas

None
