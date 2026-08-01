---
phase: 69-tenant-isolation-security-hardening
plan: 04
subsystem: api
tags: [multi-tenant, security, vendor-portal, survey]

# Dependency graph
requires: []
provides:
  - "동일 phone 다매장 벤더 실측 — 운영(5434)·로컬(5432) 양쪽 0건"
  - "운영 pin_hash 설정 벤더 0명 — R3 은 현재 악용 불가능한 잠재 결함임을 확인"
  - "69-05 로그인 변경의 사용자 영향 0 — 매장 통지·계정 병합 결정 불필요"
affects: [69-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "벤더 테이블 실제 이름은 talleres_vendors (모델 Vendor 의 tableName) — vendors 로 조회하면 relation does not exist"

key-files:
  created:
    - .planning/phases/69-tenant-isolation-security-hardening/69-VENDOR-PIN-SURVEY.md
  modified: []
---

# 69-04 — 벤더 동일 phone·상이 PIN 실측 조사

## 무엇을 했나

69-05(벤더 토큰 단일 매장 scope 전환)가 **누구의 로그인을 바꾸는지** 코드 변경 전에 측정했다.
읽기 전용 — SELECT 만 실행했고 코드·스키마·데이터 변경 0건.

## 결과

| | 활성 벤더 | 구분 phone | 다매장 phone | `pin_hash` 설정 |
|---|---|---|---|---|
| 운영(5434) | 7 | 5 | **0** | **0** |
| 로컬(5432) | 18 | 14 | **0** | — |

```sql
SELECT phone, count(*) filas, count(DISTINCT store_id) tiendas,
       count(DISTINCT pin_hash) pins
  FROM talleres_vendors
 WHERE is_active = true AND phone IS NOT NULL AND phone <> ''
 GROUP BY phone HAVING count(DISTINCT store_id) > 1;
-- 운영 0행 · 로컬 0행
```

## 판정

**영향 벤더 0명. 매장 통지 불필요. 계정 병합/분리 결정 불필요.**

69-05 의 로그인 변경(행별 PIN 검증 + 단일 매장 토큰 + 다중 통과 시 매장 선택)은
기존 사용자에게 무영향이며, 데이터 마이그레이션 없이 진행 가능했다.

## 부수 발견

운영 벤더 7명 전원의 `pin_hash` 가 NULL 이다 — **벤더 포털 로그인이 현재 어느 매장에서도 동작하지 않는다.**
따라서 R3/CR-03 은 감사 시점에도 **실제 악용은 불가능한 잠재 결함**이었다.
PIN 이 발급되기 시작하는 순간 열리므로, 69-05 를 먼저 넣은 순서가 옳았다.

## 재발 감시

다매장 벤더가 생기면 로그인 시 매장 선택 화면이 뜬다(에러 아님, 정상 흐름).
같은 phone 에 **서로 다른 PIN** 이 생긴 조합(`pins > 1`)이 CR-03 이 막으려던 지점이므로,
위 쿼리를 주기적으로 돌려 확인한다.

## 검증

- 운영(5434)·로컬(5432) 양쪽에서 동일 쿼리 실행, 결과 일치
- 테이블명은 `vendor.model.ts` 의 `@Table({ tableName: 'talleres_vendors' })` 로 확인 (추측 아님)
