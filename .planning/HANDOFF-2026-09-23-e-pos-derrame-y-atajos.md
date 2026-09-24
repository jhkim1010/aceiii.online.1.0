# 핸드오프 2026-09-23 (밤 늦게) — POS 캐하 「Pago」 완성 + 단축키 재편

이 세션은 **전부 프론트(ventago-app)** 다. API 변경 없음 → 짝 배포 걱정 없음.

---

## 1. 배포 상태

| Jenkins | 커밋 | 결과 |
|---|---|---|
| front **#777** | app `2dce94c` | SUCCESS (전 세션 POS 하단 재설계) |
| front **#778** | app `8a55d70` | SUCCESS + 컨테이너 재생성 확인 |
| front **#779** | app `f15f1468` | **SUCCESS** + `ventagoapp` 재생성 확인 (이 세션 마지막) |

→ **이 세션의 배포는 전부 끝났다.** 확인할 빌드 없음.

★ Jenkins 잡 이름은 **`api-new-coolsistema`** (API) / `front-coolsistema` (프론트).
  CLAUDE.md 의 `api-coolsistema` 는 **여전히 틀림** — 고쳐야 한다(전 핸드오프에서도 지적됨).

---

## 2. 이 세션에 들어간 것 (커밋 6건)

| 커밋 | 내용 |
|---|---|
| `67b8a25` | 잔금 자동 이월(blur 시점) · Resto 버튼 제거 · Crédito 사유를 3초 풍선으로 |
| `8a55d70` | CODEX ①: 할증 수단이 이월 목적지가 되던 것 ②: ✕ 가 결제를 안 지우던 것 |
| `522ba1f1` | 단축키가 줄을 따라감 · Tab 금액 이동 · 총액 증감 배분 · 콤보 규칙 · ✕ 제거 · Alt+C |
| `6f2e62f8` | CODEX ①: 모달 결제가 증감을 흡수 ②: 슬롯 중복 |
| `04c1fef3` | descuento·recargo 칩 중복 제거 + 세 줄 → 한 줄 |
| `f15f1468` | 금액 없이 Tab = 취소 · **`input-sku` id 복구** |

### 확정된 규칙 (다시 정하지 말 것 — 전부 사용자 결정)

- **잔금 이월**: 어떤 줄을 고치면 잔금은 「그 아래 **쓸 수 있는** 첫 줄」로. 못 쓰는 줄은 건너뛴다.
  **blur(Tab) 시점**이다 — 타이핑 한 글자마다 하면 부분 금액을 칠 수가 없다(실측).
- **단축키는 줄을 따라간다**: F9=현금(고정), Re Pág=**2번째 줄**, Av Pág=**3번째 줄**.
  셋 다 적용 후 **그 금액칸에 포커스 + 전체선택**.
- **총액 증감**: 현금은 **절대 안 건드린다**. 돈이 들어간 **비현금 맨 아래 줄**이 흡수.
  감소 시 같은 줄에서 빼되 **0 에서 멈추고** 「Sobra」를 보여 준다.
- **콤보**: 각 줄은 efectivo + **위쪽 줄들만** 제외. 아래와 겹치면 그 아래 줄을
  **첫 번째 빈 수단으로 재배정**(무작위 아님 — 재현 가능해야 한다). 남는 게 없으면 **빈 줄**.
- **Resto 버튼·✕ 버튼 둘 다 없다.** 줄 비우기 = 칸에 들어가면 전체선택되므로 `0` 한 글자.
  전체 리셋 = F9.
- **ajuste 취소** = 금액 없이 Tab. **Esc 는 카트를 비우므로 탈출구로 쓸 수 없다.**
- **Cantidad = Alt+C** (F8 은 별칭으로도 안 남김 — `pos-shortcuts-sync.spec.ts` 가
  「코드에 있는 키는 F1 목록에 다 있어야 한다」를 강제한다).

### 이미 되던 것 (새로 만들지 말 것)

- 2~4번 콤보에 **Efectivo 는 원래 없었다**.
- **할인·할증은 원래 여러 개** 들어간다(`sale_discounts`/`sale_recharges` N행, 프론트도 append).
  하나만 되는 것처럼 보인 이유는 **같은 이름이 말없이 거부**되기 때문 —
  `discounts.some(d => d.name === ...) return`. 문구 없이 거부한다(개선 여지).

---

## 3. ★ 이 세션에서 드러난 「조용히 죽어 있던」 것들

### 3-1. `input-sku` id 가 DOM 에 없었다 (고침)

`id="input-sku"` 가 `renderInput` 의 TextField 에 있었는데 MUI 가 `params.inputProps.id`
(`:r9:`)로 덮는다. `getElementById('input-sku')` 가 **계속 null** 이었고 `?.` 가 삼켰다.
→ 할인 적용 후 코드칸 복귀, tmp 모드 탈출 복귀가 **전부 죽어 있었다.**
`<Autocomplete id={SKU_INPUT_ID}>` 로 옮겨 고침. 메모리:
`mui-autocomplete-id-shadows-textfield-id`.

★ 이 세션 내내 빨갛던 `tmp-sku-editable.spec.ts` 가 바로 이걸 가리키고 있었다 —
  다만 **파일에 문자열이 있는지**만 봐서, id 가 아무 데도 안 닿는 동안 초록이었다.
  실제 불변식(Autocomplete 에 있고 `renderInput` 안에는 **없을 것**)으로 바꿨다.

### 3-2. `codex exec` 가 긴 프롬프트에서 조용히 죽는다

**exit 0 · 빈 출력.** 대조군(짧은 한 줄 / 짧은 여러 줄 / 파일 읽기 지시)은 전부 정상.
이번 세션에서 **3번 낭비했다.** 메모리: `codex-exec-dies-silently-on-big-prompt`.
쓰는 법: 짧은 프롬프트로 **읽을 파일을 지시**, `-o <파일>` 로 최종 답변 받기, `< /dev/null`.

★ 자동 CODEX 훅이 `reason=secret_pattern_in_diff` 로 건너뛰었는데,
  그 줄번호는 **누적 diff** 기준이라 이번 변경과 무관했다. `.auto-codex.SKIPPED.*.txt` 확인.

---

## 4. 검증 상태

- `tsc 0` · `eslint 0`(exit code) · **jest 681/681** — 빨간 것 없음
- 돌연변이 **21개 전부 사망**, 대조군 매번 통과. 동치 1개는 주석으로 명시
  (`repartirCambioDeTotal` 의 `Math.max(0,…)` 는 `ponerMontoEnLista` 와 중복)
- DB 끝단(로컬 store 6): sale **5171441** total 21.000 → Efectivo 5.000 + Banco 16.000

★ 브라우저 검증은 **cmux browser** 로 했다. dev 번들(3050)로 잘 됐다.
  ★ `cmux press` 는 **웹뷰에 안 닿는다**(Tab·PageUp 등). `KeyboardEvent` 를 dispatch 할 것.
  ★ 버튼은 **텍스트로 정확히 지목**할 것 — 넓은 선택자(`button.MuiButton-outlined`)로
    눌렀다가 관리자 승인 모달을 띄웠다.

---

## 5. 다음에 할 만한 것

1. **CLAUDE.md 의 Jenkins 잡 이름 수정** — `api-coolsistema` → `api-new-coolsistema`
2. 같은 이름 descuento 를 **말없이 거부**하는 것 → 이유를 보여 주기 (§2 끝)
3. **Phase 93 P1-e** — 운영에 살아 있는 인가 구멍. **사용자 결정 대기 중**:
   `manage-clients` · `manage-codigo-import` · `view-codigo-import-history` 3개 slug 가
   `functions` 카탈로그에 없어 `isAllowed()` 가 **통과**시킨다. 어느 역할에 줄지가 미결.
   상세는 `.planning/HANDOFF-2026-09-23-d-pos-pago-inline.md` §4.

---

## 6. 환경

- 3050 = `npm run dev`, 5002 = 로컬 API(`DATABASE_NAME=ventago DATABASE_PORT=5432`)
- 더미 계정 4개 비밀번호 `Dummy1234`(로컬 전용). **로그인은 사용자가 한다.**
- 검토 기록: `.team/reviews/manual-pos-derrame-{codex,resolution}.md`,
  `.team/reviews/manual-pos-atajos-{codex,resolution}.md`
