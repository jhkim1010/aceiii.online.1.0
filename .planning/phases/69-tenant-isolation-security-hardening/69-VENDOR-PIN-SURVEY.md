# 69-04 — 벤더 동일 phone·상이 PIN 실측 조사 (R3 / CR-03)

**실행:** 2026-08-01
**성격:** 읽기 전용(SELECT only). 코드·스키마·데이터 변경 0건.
**목적:** 69-05(벤더 토큰 단일 매장 scope 전환)가 **누구를 로그인 불가로 만드는지** 먼저 측정한다.

---

## 결론 (먼저)

**영향 벤더 0명. 매장 통지 불필요. 계정 병합/분리 결정 불필요.**

운영·로컬 양쪽에서 **동일 phone 이 2개 이상 매장에 걸친 조합이 0건**이고,
**`pin_hash` 가 설정된 벤더도 0명**이다. 69-05 는 데이터 마이그레이션 없이 진행 가능하다.

부수 발견: 현재 **벤더 포털 로그인은 어느 매장에서도 동작하지 않는다.** 전 벤더의 `pin_hash` 가 NULL 이라
`vendor-auth.service.ts:34-36` 의 `if (!vendors[0].pinHash) throw UnauthorizedException('PIN no configurado')`
에서 100% 차단된다. 즉 R3 은 **현재 악용 불가능한 잠재 결함**이다 — PIN 이 발급되기 시작하는 순간 열린다.

---

## 운영 (srv803182, PG18 포트 5434)

접근: `ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -c '<SELECT>'"`

| 지표 | 값 |
|---|---|
| 전체 벤더 | 7 |
| 활성 벤더 | 7 |
| distinct phone | 5 |
| **동일 phone 다중 매장 조합** | **0** |
| **`pin_hash` NULL (활성)** | **7 / 7** |
| 중복 phone (매장 무관) | 0 |

전체 행:

| id | store_id | phone | is_active | pin_hash |
|---|---|---|---|---|
| 5 | 6 | (빈값) | t | NULL |
| 7 | 6 | (빈값) | t | NULL |
| 6 | 6 | `1100001111` | t | NULL |
| 1 | 6 | `2390482309` | t | NULL |
| 3 | 6 | `jadskljf` | t | NULL |
| 4 | 6 | `kasdjfls` | t | NULL |
| 2 | 6 | `lee` | t | NULL |

전 행이 **store 6(coolsistema) 단독**이다. phone 값 다수가 테스트 문자열(`jadskljf`, `kasdjfls`, `lee`)이고
2건은 빈 문자열이다 — 실사용 벤더 데이터가 아니라 시험 입력으로 보인다.

## 로컬 (Mac PG18 포트 5432)

접근: `postgres-ventago` MCP 가 `MCP error -32603` 로 전 쿼리 실패(`SELECT 1` 포함) → 이 세션은 Mac 로컬에서
실행 중이므로 `psql -h 127.0.0.1 -p 5432` 로 직접 조회했다. PG 는 정상 리스닝 중이었다(pid 839).

| 지표 | 값 |
|---|---|
| 전체 벤더 | 18 |
| 활성 벤더 | 18 |
| **동일 phone 다중 매장 조합** | **0** |
| **`pin_hash` NULL** | **18 / 18** |
| 매장 분포 | store 1 → 13행 (pin 0) · store 6 → 5행 (pin 0) |

---

## 69-05 영향 분석

| 분류 | 정의 | 실측 | 조치 |
|---|---|---|---|
| 동일 phone · **동일** pin_hash | 수정 후 매장 선택만 추가, UX 영향 미미 | 0건 | — |
| 동일 phone · **상이** pin_hash | 수정 후 매장별 PIN 개별 입력 필요 → **통지 대상** | **0건** | **불필요** |
| `pin_hash` NULL | 현재도 로그인 불가 | 운영 7 / 로컬 18 (전량) | 69-05 와 무관, 정리 대상 후보 |

**되돌리기 어려운 작업이 사라졌다.** 69-05 는 순수 코드 변경이며 다음 사항이 성립한다:

- 데이터 마이그레이션 0건
- 매장 통지 0건
- 기존 벤더 토큰 무효화의 실제 피해자 0명 (발급된 유효 토큰이 존재할 수 없음 — 로그인 자체가 불가)

단, 69-05 는 여전히 필요하다. 결함은 데이터가 없어서 잠복 중일 뿐 코드에 그대로 있다
(`vendor-auth.service.ts:39` 가 `vendors[0].pinHash` 하나만 검증하고 `:48` 에서 전체 `vendorIds` 를 토큰에 담는다).
PIN 발급이 시작되고 한 전화번호가 두 매장에 등록되는 순간 즉시 악용 가능해진다.

---

## 승인 요청

69-05 진행에 필요한 판단은 **하나도 남지 않았다**(영향 0). 다만 아래 2건은 별도 결정 사항으로 남긴다.

1. **벤더 포털이 실제로 쓰이고 있는가?** 전 매장 PIN 미발급 상태다. 미사용 기능이라면 우선순위 재검토 여지가 있다.
2. **운영 테스트 데이터 정리** — store 6 의 phone 이 `jadskljf` / `lee` / 빈값인 7행. 이 Phase 범위 밖이며
   삭제는 별도 승인이 필요하다. 이번 조사에서는 **아무것도 지우지 않았다.**

**승인 상태:** _대기_ — 사용자 확인 후 69-05 실행.

---

## 재현 쿼리

```sql
-- 동일 phone 다중 매장 조합 (핵심 지표)
SELECT phone, count(*) AS rows, count(DISTINCT store_id) AS stores,
       count(DISTINCT coalesce(pin_hash,'')) AS distinct_pins
FROM talleres_vendors
WHERE is_active AND phone IS NOT NULL AND phone <> ''
GROUP BY phone HAVING count(DISTINCT store_id) > 1;

-- PIN 발급 현황
SELECT store_id, count(*), count(*) FILTER (WHERE pin_hash IS NOT NULL) AS pin_set
FROM talleres_vendors GROUP BY store_id ORDER BY store_id;
```
