# 73 후속 2 — 결제수단 %·선물티켓 완료 / 로그인 재설계 대기 (새 세션용)

앞선 문서: `73-NEXT.md`(작업 A·B·C + §5 미확정 2건). 이 문서는 그 이후.

---

## 0. 먼저 읽을 것

- jest 는 반드시 `NODE_OPTIONS=--max-old-space-size=2048 npx jest --maxWorkers=1 --workerIdleMemoryLimit=800MB`
  (2 워커면 랜덤 suite 가 SIGTERM 으로 죽어 간헐 실패)
- **로컬 `ventago` DB 가 생겼다**(2026-08-06 Dropbox 백업에서 복원). 이제 마이그레이션은
  로컬 5432 → 운영 5434 양쪽 적용하고 `./.planning/intel/db-schema.regen.sh` 로 레퍼런스 갱신.
- Jenkins 는 **운영 서버 위에서** 돈다(swap 0, free 1.6GB). 무거운 작업을 빌드에 넣지 말 것.

---

## 1. 완료 — 결제수단·옵션별 할증/할인 % (73-16)

전부 배포됨. 기존 결제수단 41개는 `adjust_percent` 가 NULL 이라 **설정 전까지 동작 변화 없음.**

| 구성 | 커밋 | 상태 |
|---|---|---|
| 마이그레이션 | `migrations/2026-08-06-payment-method-adjust-percent.sql` | 로컬+운영 적용, 스키마 대조 ✅ |
| 백엔드 | api `6bc00a1` | Jenkins ✅ |
| 프론트 | app `dc04024` | front #541 ✅ |

### 규칙 (바꾸려면 여기부터 읽을 것)
- 부호 있는 % 하나: 양수=Recargo, 음수=Descuento
- **옵션의 NULL = "결제수단 기본값 상속", 0 = "이 은행은 면제"** — 뜻이 다르다.
  해석 함수가 `??` 를 쓴다. `||` 로 바꾸면 면제 설정이 조용히 무시된다(테스트가 잡는다).
- % 는 **그 결제수단으로 낸 금액에만** 적용. 잔액 계산은 항상 base(상품분) 기준.
- 조정분은 Recargo/Descuento 항목으로 자동 기록 → 영수증·리포트 수정 불필요.
  재계산 전에 이전 자동 항목(`AUTO_ADJUST_FLAG`)을 걷어낸다. 안 하면 모달 재저장 시 누적된다.
- 금액은 정수 반올림 — 안 하면 `sum(결제)===totalAmount` 완납 판정이 소수점으로 깨진다.

### ★ 아직 실사용 확인 안 됨
운영에서 한 건 판매해 **Recargo 가 판매상세·영수증에 찍히는지, 상태가 Pagado 인지** 확인 필요.

계산 규칙 사본이 둘이다(불가피 — 프론트가 백엔드를 import 못 함). 바꾸면 **양쪽 같이**:
- `api-ventago/src/app/payment-methods/payment-adjust.util.ts` (테스트 16건 있음)
- `ventago-app/src/utils/payment-adjust.ts`

---

## 2. 완료(단 배포 주의) — 선물/교환용 티켓 (73-17)

POS 에 **"Temp s/ precio"** 버튼. 단가·소계·합계·할인·할증·운송을 뺀 티켓.
품목명·수량은 남긴다(교환하려면 무엇을 샀는지는 보여야 한다).

| 구성 | 커밋 | 상태 |
|---|---|---|
| 프론트 | app `aa7c806` + `cda3815` | front #543 ✅ |
| print-agent 포맷터 | root `ed0734a` | **릴리스 안 됨** |

### ★ 조용히 실패한다 — 이게 남은 일
가격을 실제로 빼는 건 **매장 PC 의 print-agent** 다. 구버전은 `hidePrices` 를 무시해
**가격이 그대로 찍힌다(오류 없이).** 선물 영수증에서 가장 나쁜 실패다.

지금은 (B) 안으로 경고만 붙여둔 상태 — 버튼 툴팁 + 전송 후 warning 토스트.
**해야 할 일**: print-agent 릴리스 태그 → GH Actions 빌드 → 각 매장 설치 →
확인 후 경고 문구 제거. (현재 태그 `print-agent-v1.1.1`, package.json 은 1.1.0 — 불일치 확인 필요)

---

## 3. 대기 — 로그인 재설계 + 하루 한마디 (사용자 결정 필요)

목업 완성: https://claude.ai/code/artifact/76012641-198b-4b79-b6a2-18e73d64a153
(Bíblico / Filosófico / Sin frase 전환 + 사진 배경 + 매장설정 + Preferencias + 데이터모델)

### 결정 대기 2건
1. **성경 번역본** — RV1960 은 상업적 재배포 제약 가능. 퍼블릭 도메인(Reina-Valera 1909) 사용 여부.
   철학 인용도 근대 이후 저자·번역은 같은 문제.
2. **범위** — (a) 스키마+공개API+로그인UI (격언은 소량 시드) / (b) 로그인UI만 / (c) 전부 다음 세션

### 설계 확정분
- "오늘의 격언"은 `날짜 + 언어 + 출처` 로 결정 → 사용자별 저장 없이 하루 고정, 새로고침해도 안 바뀜
- 로그인 **전** 화면이라 **인증 없는 공개 엔드포인트** 필요. 매장 식별자 없이 언어만 받게 할 것
- 사진: **Unsplash/Pexels 를 로그인 화면이 직접 부르지 말 것.**
  오프라인이면 화면이 깨지고, CSP 를 열어야 하고, 레이트 리밋(Unsplash Demo 50/시간)에 걸리고,
  출처 표기 의무가 있다. → **서버가 주기적으로 받아 MinIO 에 저장**하고 자기 서버에서만 제공.
  MinIO 는 이미 쓰고 있어 새 인프라 불필요.
- 기존 로그인 흐름(세션만료 경고·지점/터미널 등록 모달)은 그대로 얹힌다

---

## 4. 여전히 미해결 — jest CI (73-13)

`.github/workflows/api-tests.yml` 은 있으나 **한 번도 실행되지 않았다.**
원인은 설정이 아니라 **GitHub Actions 장애**(major_outage, 2026-08-06T15:22Z 시작).
과금 문제 아님(플랜 free, private 월 2,000분 포함, 8월 private 사용 0분).

복구 후 아래로 초록 확인 전까지 **완료로 적지 말 것**:
```bash
gh workflow run api-tests.yml --repo jhkim1010/api-ventago --ref main
```
한계: 이 워크플로는 Jenkins 배포를 막지 못한다("배포 후 통보"). 하드 게이트를 원하면
Jenkins 를 운영 서버 밖으로 빼는 것이 선행돼야 한다.

---

## 5. 이월 — 손대지 않기로 한 것

- **0원 식당 판매 3건**: 매장 11 "Asado". 결제 기록도 0이라 돈이 오간 흔적이 없어
  **의도적 미보정**(사용자 결정). 데이터는 그대로 있으니 나중에 판단 가능.
- **package-lock.json 불일치**: axios 등 21개가 lock 에 없고 electron 잔재가 있다.
  `npm ci` 불가 → `npm install` 사용(Dockerfile 과 동일). 운영 이미지도 매번 버전을
  새로 해석한다는 뜻. 재생성하려면 전체 테스트+스모크까지 묶어서.
