# 핸드오프 — 2026-08-20 · Phase 85 W1 (캐시 봉인, 미완)

`HANDOFF-2026-08-19-b-settlements-store-id.md` 에서 이어짐.

## ★ 지금 상태 — 커밋은 있으나 **push 안 됨**

```
api-ventago  647d5b7  feat(cache): getOrLoad single-flight + CacheKey 타입 강제 (Phase 85 W1, 부분)
```

**의도적으로 push 하지 않았다.** 사용자 지시가 *"스테이징 서버에서 먼저 충분히 테스트"* 인데,
main 에 push 하면 Jenkins 가 곧바로 운영에 배포한다. 다음 세션은 **스테이징 검증 후** push 한다.

## 무엇을 고치는 작업인가

`MemoryCacheService` 를 쓰는 43개 파일 전부가 `get → miss → DB → set` 3단이라, TTL 만료
순간 동시 요청이 **전부 DB 를 친다**(cache stampede). 4매장에서는 안 보이고 300매장에서 터진다.

## 한 것

- `getOrLoad(key, ttl, loader)` — 같은 key 의 loader 를 하나로 합침. 실패는 캐시 안 함.
- `CacheKey` 브랜드 타입 — `storeKey()`/`globalKey()`/`storePrefix()` 로만 생성.
  **생 문자열은 컴파일 에러.** 규약이 문서가 아니라 타입이 됐다.
- 19개 파일 전환 (참조데이터 7 · vto · attendance · jwt.strategy · subcon 4 · 공개몰 2 · 모바일 3)
- 무효화 범위를 **매장 단위**로 좁힘 (종전엔 전 매장 — 그 자체가 stampede)

## ★ 검토에서 잡힌 것 — 전부 실제 결함이었다

| # | 내용 | 잡은 주체 |
|---|---|---|
| P1 | `AUTH_USER_CACHE_PREFIX` 를 손으로 적어 실제 키와 어긋남 → 매장 정지 시 일괄 무효화가 **아무것도 못 지움** | codex |
| P1 | cut-ticket 무효화가 파일 건너 갈라짐 → 재작업 후 2분간 낡은 BOM | codex |
| P2 | 키 인코딩 `:`→`_` 가 **새 충돌** 생성 (`a:b` = `a_b`) → 남의 검색 결과 반환 | codex |
| — | `storePrefix(p,6)` 이 `s60`·`s61` 까지 삭제 | 에이전트 |

★ **P1 첫 건은 내가 쓴 spec 이 잡고 있었는데 결과를 안 읽었다.** 백그라운드로 돌려 놓고
알림만 보고 넘어갔다 — 감시 장치를 달고 안 본 것이다. 다음부터 spec 을 돌렸으면 **결과를 읽는다.**

★ 에이전트는 P2 를 **정반대로** 보고했다("`:` 치환 덕에 충돌이 사라졌다"). 치환이 한 충돌을
없애며 다른 충돌을 만든 것을 못 봤다. **에이전트 보고는 입력이지 결론이 아니다.**

## 남은 것 — 순서를 지킬 것

1. **남은 호출부 6개 전환** — `auth.service`(2블록) · `function-permission` ·
   `dashboard-admin` · `afip-issuer` · `functions`
2. **`get`/`set` private 봉인 (TASK-4)** — ★ 반드시 1 이 끝난 뒤. 먼저 봉인하면 전부
   동시에 컴파일 실패해 어디까지 고쳤는지 알 수 없다.
3. **스테이징 부하 시험** — 아래
4. codex 재검토 → push → 운영

`subcon/dashboard`·`dashboard-v2` 는 **W7 대상이라 의도적으로 미변경**(5분·60초 TTL).

## 스테이징 (살아 있음, 2026-08-20 확인)

```
ventago_staging   577MB · 309 매장 · 6,079 유저 · 163,482 판매
api_staging       내려가 있음
pgbouncer:6432    미기동
자산              /home/jhkim/phase63-staging/
```

절차와 **지난번 함정 2건**(`.env.staging` 비밀번호 낡음 / pgbouncer 미배치)이
`loadtest/README.md` 에 있다. 사용자 승인: **부하는 최대 강도로 가도 된다**(사용자 없음).
단 이 서버는 **swap 0 이고 운영 PG 가 같은 박스**다 — 시험 중 메모리를 감시할 것.

**측정할 값은 하나다: TTL 만료 순간 동시 요청 N개에 DB 쿼리가 몇 번 나가는가.**
지금 N번 → 고친 뒤 1번이어야 한다. `pg_stat_statements` 의 `calls` 증분으로 본다.

## 기록만 하고 안 고친 것

- ★ **`mobile-stock` 캐시 키에 지점이 없다.** 응답 `stock` 은 `ownBranchId` 로 계산되는데
  키는 `store+product` 뿐 → 같은 매장 **다른 지점 판매원이 10초간 남의 지점 수치**를 본다.
  기존 동작이나 실제 오답을 주는 경로다. 키 범위를 바꾸면 히트율·의미가 달라져 별건.
- `afip-issuer` — 운영 호출부가 **없다**(spec 만 호출). storeId 를 얻을 곳이 없어 미전환.
- `CrudService.delete()` 가 캐시를 무효화하지 않는다(기존 결함, 소프트삭제라 실사용 노출 없음).
- `attendance:report` · `vto:enabled` 쓰기 경로 무효화 없음(TTL 의존, 기존 설계).
