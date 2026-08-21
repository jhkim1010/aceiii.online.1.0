# Stage 0 codex 검토 — 수용/반박 (2026-08-22)

원본: `.team/reviews/w6c0-codex.md` · diff: `.team/reviews/w6c0-diff.txt`

| # | 심각도 | 지적 | 결정 |
|---|---|---|---|
| 1 | **CRITICAL** | `restoreContract` 는 업로드된 파일 안의 사용자 통제 데이터 — 손으로 넣으면 잠금이 열린다 | **수용, 전면 재작성** |
| 2 | HIGH | 소스 대조가 함수 끝을 안 찾아 파일 끝까지 훑는다 | **수용** |
| 3 | HIGH | 정규식이 `backupData?.x` · `['x']` · 구조분해를 놓친다 | **수용(변형)** |
| 4 | MEDIUM | 서비스 경계에서 실제로 막히는지 검증 안 함 | **수용** |
| 5 | MEDIUM | UI 문구가 백엔드 동작과 불일치 | **수용 — 백엔드를 사실로 만들어 해소** |
| 6 | 정리 | 응답에 내부 경로 `.planning/...` 노출 | **수용, 제거** |
| — | 이상 없음 | purge 다이얼로그 문구 · 정보 노출 | 그대로 |

---

## 1 [CRITICAL] — 내 잠금은 열쇠를 문에 붙여 놓은 잠금이었다

첫 판은 백업 파일이 `restoreContract` 를 싣게 하고 **그 선언을 믿었다.**
그런데 그 파일은 superadmin 이 **업로드하는 것**이다. 기존 119개 백업에

```json
"restoreContract": { "version": 1, "purpose": "clone", "tables": [] }
```

한 줄만 손으로 넣으면 거부 사유가 0개가 되고 위험한 엔진이 그대로 돌았다.

★ 이 저장소가 이미 배운 **"판정의 근거는 저장의 근거와 같아야"** 를 그대로 어겼다.
  파일의 *주장*을 권위로 삼은 것이다.

**재작성**: 판정 권한을 서버로 옮겼다.
- `RESTORE_ENGINE_STATUS`(서버 상수) 가 `blocked` 인 동안 **무조건 거부**. 요청으로 못 바꾼다
- 잠금이 풀린 뒤의 게이트는 파일의 *주장*이 아니라 **실제 내용**을 센다
  (`unsupportedContentKeys()` — 빈 배열은 안 세고, `tables{}` 안까지 연다)
- 파일이 `restoreContract` 를 실어 보내도 **메타 키로 무시**한다

★ 플래그만 `enabled` 로 바꾸면 **TS2367 로 빌드가 깨진다**(리터럴 좁히기).
  의도한 것이고, 그 이유를 상수 옆에 적어 뒀다. 비교문을 지우면 spec 이 깨진다.

## 2·3 [HIGH] — 소스 대조

- 함수 본문을 **괄호·꺾쇠 깊이로** 잘라 낸다. ★ 첫 시도는 반환 타입
  `): Promise<{ ... }> {` 의 중괄호를 잡아 **0개를 세고 통과할 뻔했다** — 대조군으로 발견.
- 정규식은 `backupData?.x` 까지 넓혔고, **분석할 수 없는 표기를 만나면 실패**하게 했다
  (`backupData['x']` · `backupData` 자체 구조분해 · 별칭 대입).
  놓친 것을 "없다" 로 읽지 않는 것이 핵심이다.
- **반박(부분)**: codex 는 AST 파싱을 권했다. 지금은 채택하지 않는다 —
  Stage 0 의 목적은 차단이고, 대조는 보조 장치다. 대신 **분석 불가 표기를 실패로
  만들어** 정규식이 조용히 틀리는 경우를 없앴다. 엔진을 handler registry 로 바꾸는
  Stage 3 에서 이 대조 자체가 불필요해진다(그때 registry 에서 목록을 파생).

## 4 [MEDIUM] — 서비스 경계

`restoreStoreFromBackup()` 을 직접 호출해 **`BadRequestException` 이 나고
`sequelize.transaction()` 이 한 번도 안 불렸는지** 단언한다.

## 검증 — 대조군으로 차단력을 증명했다

| 대조군 | 결과 |
|---|---|
| 서버 상수를 `enabled` 로 | **컴파일 실패(TS2367)** — suite 자체가 안 돈다 |
| 서비스에서 검사 호출 제거 | **1건 실패** |
| 엔진 키 선언에서 하나 삭제 | **2건 실패** |
| 원복 | **12/12 통과** |

## codex 가 확인 못 한 것 — 내가 직접 셌다

> "별도의 복원 구현이나 직접 DB 복사 경로가 저장소에 존재하는지는 확인할 수 없다"

- `restoreStoreFromBackup` 호출부: **`store.controller.ts:115` 하나뿐**
- 다른 복원 엔드포인트: `admin-console.controller.ts:93 POST tenants/:storeId/restore`
  → **soft-delete 되돌리기**(플래그만 뒤집음). FK 복사 없음, 위험 아님
- `cloneStore`/`copyStore`/`duplicateStore`/`importStore`: **0건**
