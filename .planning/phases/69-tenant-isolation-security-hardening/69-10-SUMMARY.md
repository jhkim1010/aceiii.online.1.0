---
phase: 69-tenant-isolation-security-hardening
plan: 10
subsystem: ops
tags: [deploy, runbook, uat, multi-tenant, security]

# Dependency graph
requires:
  - phase: 69-09
    provides: "회귀 관문 npm run test:tenant — 배포 후 판정 기준"
provides:
  - "배포 순서(app → api) · env 표 · 롤백 3단계 런북"
  - "운영 실증 UAT — R1 소켓 프로브, R3/R5 API 프로브, R4 부팅 로그"
  - "브라우저/실계정 잔여 체크리스트 (enforce 회귀는 '빈 목록' 으로 나타나므로 필수)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "소켓 인증 도입 배포는 app 먼저 — 반대로 하면 구 프론트 소켓이 조용히 끊긴다"
    - "enforce 회귀는 에러가 아니라 빈 목록 — 로그 지표만으로 무회귀를 선언하면 안 된다"

key-files:
  created:
    - .planning/phases/69-tenant-isolation-security-hardening/69-DEPLOY-RUNBOOK.md
    - .planning/phases/69-tenant-isolation-security-hardening/69-UAT.md
  modified: []
---

# 69-10 — 배포 런북 + 운영 UAT

## 무엇을 했나

**1) `69-DEPLOY-RUNBOOK.md`** — 배포 순서(app → api 와 그 이유), env 표(기본값·운영값·의미),
배포 직후 확인 명령 3종, 롤백 3단계(파생만 완화 → 격리 전체 완화 → 코드 롤백), 사용자 영향 공지, 회귀 관문.

**2) `69-UAT.md`** — 운영에서 실제로 확인한 것과 확인하지 못한 것을 구분해 기록.

## 운영 실증 결과

| 결함 | 결과 | 증거 |
|---|---|---|
| R1 소켓 무인증 room 가입 | **PASS** | 무인증 소켓 프로브 → `join_error` ×3 → `auth_error: Auth timeout` → 서버가 disconnect. join 0회 |
| R3 벤더 토큰 | **PASS(부분)** | 운영 `POST /vendor-portal/auth/login`(없는 번호) 401, `/me` 무토큰·구토큰 401 |
| R4 파생 스코프 | **PASS** | 부팅 로그 `derivedMode=enforce 대상=39`, observe 라인 0 |
| R5 fail-closed | **PASS** | 무토큰 `/products` 401, `TENANT-CTX` 차단 로그 0건 |
| R2 correct-today | **코드/테스트 확인** | 운영 실증은 매장 계정 토큰 필요 — 범위 밖. 회귀 스위트 R2 4종 통과 |
| 무회귀 | **PASS** | 당일 로그 6,240줄에 `[error]` 0 · 403 0. 빌드 #592/#593 SUCCESS, 컨테이너 healthy |

배포 순서도 사후 확인했다 — 프론트 21:04 UTC(소켓 인증 커밋 `f8c3a2b` 포함) → api 22:46/23:23. 런북 규칙과 일치.

## 이 UAT 가 증명하지 못하는 것

**enforce 회귀는 에러가 아니라 빈 목록으로 나타난다.** 로그 지표(에러 0·403 0)는 "터지지 않았다" 만 말할 뿐
"목록이 채워진다" 는 말하지 않는다. 그래서 UAT 문서 말미에 브라우저/실계정 체크리스트 7항목을 남겼다
(POS 판매·상품 목록·correct-today 저장·팀 채팅/MP 알림·프린터·벤더 앱·지점 전환).

## DDL

**0건.** Phase 69 전체에서 마이그레이션 대상 SQL 은 없다. 변경된 것은 코드와 `.env` 키뿐이다.

## Commits

- 루트 레포 docs 커밋 (69-07/09/10 SUMMARY + 런북 + UAT + OBSERVE-HITS)
