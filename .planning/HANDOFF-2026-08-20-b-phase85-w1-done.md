# 핸드오프 — 2026-08-20 (밤) · Phase 85 W1 **완결 · 배포됨**

`HANDOFF-2026-08-20-phase85-w1-cache.md` 에서 이어짐. 그 문서의 「남은 것」 1~4 를 전부 끝냈다.

## 상태: 운영 배포 완료

```
api-ventago  c19fc41  test(cache): kanban 키 배선 spec
             dc50bde  feat(cache): 남은 호출부 전환 + get/set 봉인 (Phase 85 W1 완결)
root         5ee0fd2  chore: 서브모듈 포인터 W1 완결 + 부하 시험 기록
Jenkins      #760 SUCCESS · api_ventago 재생성 · 4워커 online(228~250MB) · 5xx 없음
```

## ★ 이전 핸드오프의 사실관계 정정 2건

1. **"push 안 됨" 은 틀렸다.** W1 부분(`76be0ce`)은 이미 origin/main 에 있었다.
2. **"남은 호출부 6개" 는 9블록(8파일)이었다.** grep 이 `.get<DashboardV2Response>(` 처럼
   **타입명에 숫자가 든 제네릭**을 놓쳐 `salesDashboards` 가 목록에서 빠져 있었다.
   (정규식 문자클래스에 `0-9` 가 없었다.)

## 한 것

- 남은 9블록 전환 — functions · dashboard-admin · salesDashboards · function-permission ·
  auth.service ×2 · afip-issuer · subcon dashboard ×2 · dashboard-v2
  (W7 유예분이었던 subcon 3블록은 **봉인의 전제조건**이라 앞당겼다 — 사용자 승인)
- **TASK-4 봉인 완료**: `get`/`set` 이 private. 3단 패턴이 컴파일 에러다.
- 키 단일 출처 2개 신설: `perm-cache-key.ts` · `dashboard-cache-key.ts`
- `getOrLoad` 에 `shouldCache` 옵션(afip 폴백 비캐시) · `getOrLoadWithMeta` · `has()`

## ★ codex 검토에서 잡힌 실제 결함 2건 — 둘 다 **기존 getOrLoad 의 결함**

| # | 내용 |
|---|---|
| P1 | loader 가 도는 동안 무효화가 들어오면 `delete` 는 아직 없는 키를 지우고, 곧이어 loader 가 **무효화된 옛 값을 새로 캐시**한다. 권한 경로에서는 "권한을 회수했는데 최대 5분간 계속 쓸 수 있다". **원격(Redis) 경로도 같다.** |
| P2 | loader 가 첫 await 전에 같은 key 로 재진입하면 아직 대입 안 된 `entry.promise`(undefined) 를 await 해 **조용히 undefined 를 정상 응답으로** 받는다. |

수정: inFlight 엔트리에 `invalidated` 표시 + 무효화 4경로(로컬 3 + 원격)를 같은 헬퍼로 통일 /
loader 를 한 마이크로태스크 미룸. **spec 12건 추가, 전부 mutation 검증**(해당 코드를
되돌리면 실제로 실패하는 것을 확인 — 통과가 다른 이유로 나는 게 아니다).

## 스테이징 부하 시험 결과 (4워커 · ventago_staging)

| 시험 | main85 (W1 이전) | w1full |
|---|---:|---:|
| `categories/by-store` 동시 100 · DB calls | **81** | **9** (−89%) |
| `auth/me` 동시 100 · DB calls | 1387 | 1346 (−3%) |
| `auth/me` p95 | 0.935s | 0.780s |

★ w1full 의 9건 내역 = 카테고리 loader **4회** + jwt 유저조회 **4회** + 측정 1.
**100 동시 요청에 워커당 정확히 1회** — 프로세스 로컬 캐시의 이론적 하한(1 이 아니라 4)이다.

★ 정확성: 워커 간 무효화 전파 60/60 최신(첫 최신 **20ms**) · 부하 중 churn 750회 낡음 0 ·
운영 redis 구독자 시험 전후 4 유지(격리 확인) · 운영 DB 무변경.

상세·함정은 `loadtest/README.md` 「실행 기록 (2026-08-20 밤)」 과 `loadtest/phase85/README.md`.

## ★ 다음 세션이 알아야 할 것

1. **`/me` 는 W1 이 거의 못 줄였다(3%).** 워밍 상태에서도 **11쿼리**를 낸다 —
   users · stores · store_apps ×2 · role_functions · user_functions · cash_registers ·
   roles · functions 가 **전부 미캐시**다. 권한맵 캐시 자체는 정상 동작한다(계측 확인:
   `perm:g:39:me-map:6:21`, 워커당 1회 miss 후 전부 hit). **이 11쿼리가 W7 의 진짜 대상이다.**
2. **배포 방식이 바뀌면 결론이 뒤집힌다.** 키 형식을 바꾸는 변경이 안전한 이유는
   `docker compose up -d`(컨테이너 통째 교체)라 구/신 워커가 공존하지 않기 때문이다.
   **`pm2 reload` 로 바꾸면 구/신 키 형식이 같은 Redis 채널에 섞인다.**
3. **부하 시험에는 대조군을 반드시 함께 돌릴 것.** churn 시험은 P1 경쟁에 민감하지 않다 —
   수정 이전 이미지로도 낡음 0 이 나온다. 그 결함 검증은 단위 spec 이 한다.
4. **스테이징 테이블 14개가 아직 없다**(`stock_balances` · `box_settlements` · `billing_*` 등).
   그쪽을 시험하려면 먼저 만들어야 한다. 근본은 복원본 재생성.

## 기록만 하고 안 고친 것 (이전 핸드오프에서 이월)

- ★ **`mobile-stock` 캐시 키에 지점이 없다** — 같은 매장 다른 지점 판매원이 10초간 남의 지점
  수치를 본다. 기존 동작이나 실제 오답을 주는 경로다.
- `CrudService.delete()` 가 캐시를 무효화하지 않는다(소프트삭제라 실사용 노출 없음).
- `attendance:report` · `vto:enabled` 쓰기 경로 무효화 없음(TTL 의존, 기존 설계).
- Redis 가 죽으면 무효화가 전파되지 않아 워커별로 TTL(최대 5분)까지 낡은 권한을 준다.
  기존 성질이며 이번에 바꾸지 않았다. codex 는 이것을 정책 결정 사항으로 올렸다.

## 스테이징 리그 (지금 살아 있음)

`api_staging`(5012, 이미지 `api-staging:w1full`) · `ventago_redis_staging` · pgbouncer 6432 가
**켜져 있다.** compose 는 `restart:'no'` 라 재부팅하면 안 뜬다. 남겨 두면 메모리 ~400MB 를
쓰지만 다음 시험을 바로 이어서 할 수 있다. 이미지 4개(`main85` / `w1` / `w1full` / `dbg`)도
비교용으로 남겨 뒀다 — `w1` 이 P1 수정 이전 **대조군**이라 특히 지우지 말 것.
