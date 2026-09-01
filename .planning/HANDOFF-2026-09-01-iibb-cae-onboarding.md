# 핸드오프 2026-09-01 — IIBB 관할 · CAE 중복 차단 · 가입 즉시 개통

**전부 배포·검증 완료. 미커밋 없음.** 다음 세션은 「바로 이어서 할 일」부터.

```
api-ventago  c0d781f → 246d5d1   (Jenkins #844·845·846·847·848 전부 SUCCESS)
ventago-app  b7b4c49 → 5869788   (Jenkins #695·696·697·698 전부 SUCCESS)
루트          8e17002 → 03505cd
```

---

## 바로 이어서 할 일 (우선순위 순)

### 1. ★ coolsistema(store 6) 발급을 SOAP 직접으로 — **검증부터**

사용자 요청. **아직 아무것도 안 바꿨다.**

```
store 6 coolsistema   provider=ws    production=TRUE   ← 실제 운영
store 9 ACE           provider=soap  production=FALSE  ← homologación 전용
```

★★★ **SOAP 경로는 운영에서 한 번도 실행된 적이 없다.** store 9 의 soap 은
전부 시험 환경이고 인증서도 `coolsyncrohomo1`(homo 전용)이다.
store 6 을 바꾸면 **운영 AFIP 에 SOAP 로 처음 발급**하는 것이 된다.

확인할 것:
1. `/app/certificates/coolsistema/cert` 가 **운영 WSFE 로 유효한가** (만료일·AFIP 등록)
   — 컨테이너에 `openssl` 이 없어 못 읽었다. 호스트에서 읽거나 다른 방법 필요.
2. **채번 연속성** — SOAP 는 `getLastBillNumber` 로 AFIP 에 직접 묻는다.
   게이트웨이가 관리하던 번호와 어긋나지 않는지.
3. **TA 토큰 캐시 충돌** — `/app/certificates/coolsistema/token/` 을 게이트웨이와
   **공유**한다. Ventago 가 직접 TA 를 받으면 게이트웨이 발급이 같이 죽을 수 있다.

전환은 한 줄이고 복귀도 한 줄:
```sql
UPDATE store_configs SET afip_provider='soap' WHERE store_id=6;   -- 복귀: 'ws'
```

★ **화면에는 이 항목이 없다** (프론트·DTO 모두 `afipProvider` 참조 0건).
  DB 에만 있고 `AfipVoucherService.resolveProvider()` 한 곳에서만 읽는다.
  화면 추가는 **동작을 확인한 뒤에** 할 것 — 검증 안 된 선택지를 올리면 누가 누른다.

### 2. ★ `dbtunnel` 전용 계정 — 내가 만든 위험을 닫는다

DBeaver 접속용으로 `~/.ssh/id_dbeaver`(**passphrase 없음**)를 만들어
서버 `jhkim` 계정에 등록했다. 그런데 `jhkim ALL=(ALL) NOPASSWD: ALL` 이라
**그 키 하나가 곧 root** 다(codex CRITICAL).

현재 제한: `permitopen="127.0.0.1:5434",no-agent-forwarding,no-X11-forwarding`
→ 5433(PG10) 등 다른 포트로는 못 간다. 하지만 셸은 열린다.

해결: sudo 없는 전용 계정을 만들고 키를 옮긴다. DBeaver 는 User Name 한 칸만 바꾼다.

★★ **SSH 키 제한과 DBeaver 의 충돌 조합**(4번 실패하고 알아냄):

| 옵션 | 결과 |
|---|---|
| `restrict` | ✗ PTY 를 막는데 DBeaver 가 요청 → `Connection reset` |
| `command="…"` (어떤 형태든) | ✗ 세션 동작을 건드려 실패 |
| **`permitopen=…`** | **✓ 동작** — 포워딩 목적지만 제한 |

### 3. 사용자 확인 대기 (3개)

- DBeaver `Test Connection` 통과 여부 (마지막 확인 못 받음)
- `/configuracion/` 중복 이름 저장 시 «Ya existe…» 안내가 뜨는지
- Facturación 에서 IIBB xlsx 다운로드가 열리는지

### 4. 미해결 위험 (codex 점검)

| 심각도 | 항목 |
|---|---|
| CRITICAL | **PG10 `0.0.0.0/0 md5`** · 126 테넌트 · EOL 2022-11 |
| HIGH | 앱 포트 7개 직접 공개 · pgbouncer 5432 평문 |
| — | ufw inactive, iptables INPUT ACCEPT |

★★★ **방화벽으로 막으면 매장이 즉시 죽는다.** codex 권고 순서:
`① 72시간 접속원 수집(읽기 전용, 안전) → ② 권한 조사 → ③ 보호 경로 병행 구축
→ ④ 매장 소수씩 이전 → ⑤ 마지막에 0.0.0.0/0 제거`
**①을 건너뛰고 ③~⑤를 하면 안 된다.**

절차는 스킬로 저장했다: `.claude/skills/revision-servidor-produccion/`

### 5. 작은 것들

- 지점 16 `HELGUERA` 주(州) 미설정 — 그 지점 CF 판매 발급 시 미확정이 생긴다
- 크레딧 노트 음수 처리 — store 6 에 NC 0건이라 **실제 데이터로 검증 못 함**
- Dropbox `todas/` 보존 정책 미정 (자동 삭제 안 걸어 둠)

---

## 이번 세션에 한 일

### 백업 + 자동 복구 시험
126개 테넌트 DB 백업이 9개월 전이 마지막이었다. 이제 매일 돈다.
`운영 01:30 덤프 → 서버2 03:00 당겨와 표본 4개 실제 복원 → 운영 04:20 부재 감시`
★ 복원 «성공» 을 믿지 않고 **덤프의 테이블 수와 대조**한다.
상세: `scripts/backup/README.md`

### IIBB (Convenio Multilateral) 관할
★★★ **관할은 구입자 주소다.** 판매자·지점 주소가 아니다(사용자 정정).
지점으로 폴백하면 화면에 그럴듯한 값이 미리 차서 **판매원이 구입자를 안 물어본다.**
그래서 폴백 «경로 자체» 를 없앴다. 보고서에만 옛 전표용 폴백이 남아 있다.

- 발급 시 관할 필수. 못 정하면 **AFIP 을 부르기 전에** 거부
- `GET /afip/iibb` · `/afip/iibb/xlsx` (회계사 Hoja1 형식 + Resumen 시트)
- 기간은 **아르헨티나 달력**으로 자른다 (UTC 면 말일 21~24시가 다음 달로 넘어감)
- 크레딧 노트는 **음수**로 싣는다
- 마이그레이션 3건 적용(로컬 5432 + 운영 5434 대조 완료)

### CAE 중복 차단 + verificar 해소
CAE 수신 후 저장이 실패하면 판매가 `en_progreso` 로 남고 10분 뒤 재클레임이
열려 **두 번째 CAE** 가 나갔다. 이제 `verificar` 로 못박는다.
`verificar` 를 푸는 경로가 **어디에도 없었다** → 진단·해소 화면을 새로 만들었다.
★ 조회는 발급 provider 와 분리(`ConsultorAfip`) — 게이트웨이 매장도 SOAP 로 조회.
★ 붙이기는 수신자·금액을 대조한다. 번호 존재만으로 붙이면 남의 전표를 귀속시킨다.

### 가입 즉시 개통 + 3일 시한
인증 끝나면 매장을 바로 만들고, 3일 내 미승인 시 자동 정지(2일차 텔레그램 예고).
★ 만료 로직이 개통된 신청을 `expired` 로 바꾸면 정지 크론이 영영 못 잡는다 → 제외.

### 상품 삭제 + 중복 이름 409
- 자식 있는 마드레는 **실제 삭제 불가**(parent_id 가 SET NULL → 고아). 소프트 삭제로.
- CodigoVista `Borrados` 체크박스 + `Restaurar`
- 중복 이름 500 → **409**. 전역 필터에서 처리 —
  `(name, store_id)` 유니크가 **12개 테이블**이라 개별로 고치면 빠뜨린다.

---

## 다음 사람이 알아야 할 함정

1. **jest 「N passed」는 무엇이 통과했는지 말하지 않는다.** 컴파일 깨진 suite 는
   조용히 빠진다. `Test Suites:` 를 함께 볼 것. 돌연변이의 `Tests: 0` 은 미실행이다.
2. **돌연변이가 컴파일을 깨뜨리면 그 자체가 좋은 신호** — 타입 시스템이 이미 막고 있다.
3. **느린 쿼리 상위는 거의 항상 레거시 임포트·일회성 정리다.** 거르지 않으면
   «시스템이 느리다» 로 오독한다. 진짜 지표는 «호출 많은 쿼리가 빠른가»
   (실측: 오늘 API 689건 중 300ms 초과 1건, 핫패스 0.0~0.2ms).
4. **화면 깜빡임이 성능이 아닐 수 있다.** 이번엔 500 반복이었다.
5. **`nc -z` 로는 `permitopen` 을 검증할 수 없다** — 로컬 리스너만 본다.
6. **`Details >>` 한 줄이 추측 네 번보다 빠르다.**
