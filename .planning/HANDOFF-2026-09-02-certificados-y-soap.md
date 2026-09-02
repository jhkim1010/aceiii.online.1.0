# 핸드오프 2026-09-02 — 인증서 자가 발급 · SOAP 전환 · 설정 UX

**전부 배포·검증 완료. 미커밋 없음.** 앞 세션은 `HANDOFF-2026-09-01-iibb-cae-onboarding.md`.

```
api-ventago  246d5d1 → 066409c   (Jenkins #849~#857 전부 SUCCESS)
ventago-app  5869788 → 62a71e3   (Jenkins #695~#703 전부 SUCCESS)
루트          5083976 → f7e9a8c
```

**추가 (2026-09-02 오후):** 아래 「할 일 2번」(인증서 경로 분리)을 끝냈다.
`api-ventago 066409c → 4a86443` (Jenkins #858·#859 SUCCESS, blue/green 무중단).
1번(store 6 첫 SOAP 발급)은 **여전히 미검증** — 사람이 화면에서 발급해야 한다.

---

## 바로 이어서 할 일 (순서대로)

### 1. ★★★ store 6 첫 SOAP 발급 확인 — **아직 미검증**

`store_configs.afip_provider` 를 `'soap'` 으로 바꿨다(2026-09-01). **발급(쓰기) 경로는
운영에서 아직 한 번도 안 돌았다.** 읽기(WSAA 로그인·FECompUltimoAutorizado·
FECompConsultar)는 실호출로 실증했다.

- `afip_auto_issue = false` 라 **첫 발급이 수동**이다 — 사람이 화면에서 보는 앞에서 나간다
- 전환 시점 채번 대조 완료: AFIP 마지막 = 우리 DB max → **다음은 A(tipo 1)=81, B(tipo 6)=123**
- 실패 시 문구로 갈린다:
  - `AFIP 거부: <코드>` → **확정 실패, 재시도 안전**
  - `발급 여부 확인 불가` → **재발급 절대 금지.** verificar 화면에서 처리
- 되돌리기 (앱 재시작 불필요, 설정을 요청마다 읽는다):
  ```sql
  UPDATE store_configs SET afip_provider='ws' WHERE store_id=6;
  ```

### 2. ~~인증서 저장 경로를 Ventago 전용으로 분리~~ — **완료 (2026-09-02, api `4a86443`)**

**단계 1·2 를 한 번에 끝냈다.** 레거시 폴더를 통째로 마운트하는 대신
`coolsistema` **한 폴더만 중첩 bind mount** 했기 때문에, 「나중에」로 미뤄 뒀던
단계 2(레거시 마운트 제거)가 같은 배포에서 함께 달성됐다.

```yaml
- /var/lib/ventago-certs:/app/certificates
- /var/lib/jenkins/workspace/certificados/coolsistema:/app/certificates/coolsistema
```

★★ **핸드오프에 적혀 있던 「복사」는 하면 안 되는 것이었다.**
`coolsistema/.lastTokens` 는 캐시가 아니라 **게이트웨이와의 상호 조정 장치**다.
유효 TA 가 살아 있는데 재로그인하면 WSAA 가 `alreadyAuthenticated` 를 내고,
우리 코드는 그때 **같은 파일**을 다시 읽어 그 TA 를 쓴다
(`afip-soap.client.ts:287`). 복사해 갈라 놓으면 두 시스템이 각자 캐시를 갖게 돼
한쪽이 **최대 12시간 발급 불가**가 된다. 중첩 마운트는 inode 가 동일하다.

★ 심볼릭 링크도 안 된다 — `afip-cert-watch.service.ts:154` 가 `entry.isDirectory()`
로 거르는데 심볼릭 링크는 여기서 **false** 라 만료 감시에서 조용히 빠진다.
(CODEX 가 짚었다. 나는 심볼릭 링크를 제안하려던 참이었다.)

`coolsyncrohomo1`(store 9, homo)은 우리 것뿐이라 `/var/lib/ventago-certs/` 로 복사했다
(레거시 원본은 그대로 뒀다).

**검증 (전부 실측):**

| 항목 | 결과 |
|---|---|
| 컨테이너가 보는 폴더 | 123개 → **2개** |
| `.lastTokens` inode | host 레거시 = 컨테이너 = **6032293** (동일 파일) |
| TA 기록 | 프로브 실행 후 그 inode 의 mtime 갱신 확인 |
| 레거시 부모 도달 | `No such file or directory` — **남의 개인키 109개가 안 보인다** |
| 실호출 | WSAA 로그인 + `FECompUltimoAutorizado` → **A=80 / B=122** (DB max 와 일치) |

★ 그 실호출에 쓴 것이 `api-ventago/scripts/afip-probe-lectura.js` 다 —
**발급 없이** 인증서 경로를 확인하는 진단이다. 배포 검증에 계속 쓸 것.
`FECAESolicitar` 는 절대 넣지 말 것.

**되돌리기**: `docker-compose.yml` 의 volumes 두 줄을 `- ../certificados:/app/certificates`
한 줄로 되돌리고 재배포. 호스트 파일은 건드리지 않았으므로 그것으로 끝이다.

**남은 것**: `/var/lib/ventago-certs` 는 **어떤 백업에도 안 들어간다**(레거시 폴더도
마찬가지였으므로 회귀는 아니다). 신규 매장이 여기에 개인키를 만들기 시작하면
백업 대상에 넣어야 한다.

### 2-b. slug 경로 검증 (같은 배포에 포함, CODEX 지적)

`coolUser` 가 검증 없이 `path.join` 에 들어가고 있었다. 출처가 셋인데 셋 다 무검증:
`POST /afip/issuers` 의 자유 문자열(`@IsString()` 뿐) · 게이트웨이 HTTP 응답 · 환경변수.
`..` 한 조각이면 폴더를 벗어나는데 **CSR 생성 경로는 거기에 파일을 쓴다** —
남의 테넌트 개인키를 덮어쓸 수 있었다. 조회가 아니라 파괴다.

지적은 한 곳이었지만 같은 형태를 전수로 세어 **경로를 만드는 3곳 전부** 막았다
(`carpeta` · `soap-direct` · `padron`) + DTO `@Matches`.
검증기 `src/app/afip/cert-slug.ts`, 시험 18건.

### 2-c. (옛 계획 — 참고용) 인증서 저장 경로를 Ventago 전용으로 분리

**사용자 결정(2026-09-02): 이전 버전 시스템(cool-invoice)은 대상이 아니다.
Ventago DB 안의 매장만 발급한다.**

그런데 지금 `AFIP_CERTS_DIR=/app/certificates` 가
`/var/lib/jenkins/workspace/certificados`(레거시 109개 짝이 있는 폴더)로 마운트돼 있다.
→ **새 매장이 「Generar CSR」 을 누르면 레거시 폴더 안에 Ventago 폴더가 하나씩 생긴다.**

단계 1 (권장 순서: **위 1번 확인 뒤에**):
- `AFIP_CERTS_DIR` 을 Ventago 전용 경로로 (호스트도 별도 경로, `0700`, 소유자 앱 사용자)
- `coolsistema/{cert,key}` **한 쌍만** 새 경로로 복사 (store 6 이 지금 이걸로 발급한다)
- 코드 변경 거의 없음 — 환경변수 + compose 마운트. 되돌리기는 환경변수 원복

단계 2 (나중): 레거시 폴더 **마운트 자체를 제거**. 그러면 api 컨테이너(root)가
109개 남의 개인키를 읽을 수 있는 상태가 사라진다 — 백로그의 「인증서 폴더 권한」이 소멸한다.

★ 한 번에 둘을 바꾸지 말 것. 첫 발급이 실패했을 때 원인이 갈리지 않는다.

### 3. AFIP 포털 가이드 문구 실사

`Configuración › Preferencias › Ventas` 의 접이식 「📖 Cómo obtener el certificado en AFIP」
는 **문서 기준으로 썼다.** 실제 포털을 한 번 따라 해 보고 메뉴 이름이 다르면 맞출 것.

---

## 이번 세션에 한 일

### 인증서 자가 발급 (신규 기능)

SOAP 발급에 필요한 X.509 는 **업로드 경로가 어디에도 없었다.** 손으로 서버에 넣은
파일뿐이라 게이트웨이 시절 폴더가 있는 store 6 말고는 SOAP 으로 넘어갈 수 없었다.

- ★ 단위는 **CUIT** — 지점이 아니다. AFIP 은 CUIT 에 발급하고, 같은 CUIT 의 여러
  punto de venta 는 인증서 하나를 공유한다. 키는 `(store_id, cuit)`
- **모델 B**: 서버가 키쌍+CSR 생성 → 사용자는 AFIP 에서 `.crt` 만 받아 업로드.
  **개인키가 서버를 안 떠난다.** openssl 불필요(컨테이너에 없다 → node-forge)
- 개인키는 **DB·MinIO 둘 다 금지**:
  MinIO 는 `GET /minio/:filename` 이 `@Public()` 무인증, DB 는 백업으로 퍼진다(매일 서버2).
  파일 `0600`, 테이블(`afip_certificados`)은 상태·메타데이터만 — **본문 컬럼이 없는 건 일부러**
- 업로드 검증 4종 — 하나라도 새면 실패가 **발급 시점**으로 미뤄지고 WSAA 는 원인을 안 알려준다:
  CUIT 일치 · **개인키 modulus 일치** · 만료 · **운영/homo 일치**
- `POST /afip/cert/csr` · `POST /afip/cert/upload` · `GET /afip/cert`
- 화면: 「Certificado digital AFIP」 카드 + WooCommerce 형식 접이식 가이드

★★ **배포 직후 결함을 내가 만들고 고쳤다** (`5a13097` → `fa46540`).
`generarCsr` 이 새 키를 곧바로 `key` 에 덮어써서 「Renovar」 를 누르면 발급이 즉시 죽었다.
그 폴더는 **게이트웨이와 공유**라 `coolsistema/key`(2019년부터 운영)를 덮었으면
게이트웨이 발급까지 같이 멎었다. 가이드에 「새 것을 올릴 때까지 기존 인증서로 계속
발급된다」고 써 놓고 코드는 정반대였다 — **문구가 거짓이었다.**
→ `key.new` 로 미루고, 검증 통과 후에만 짝을 교체하며 옛 짝을 `.bak` 으로 남긴다.

### store 6 → SOAP 전환

검증 3항목을 실호출로 실증한 뒤 전환했다 (상세는 09-01 핸드오프).
인증서 운영 CA·키 짝 확인 · 채번 완전 일치 · TA 캐시는 설계상 공유.

★ 전환 직전 **잘못된 경보를 한 번 냈다.** AFIP `FEParamGetCondicionIvaReceptor` 표에
`Id 5 (Consumidor Final) → Cmp_Clase "C/49"` 라 「Factura B 가 전부 거부된다」고 봤는데,
store 9 가 SOAP 으로 낸 전표 2건이 **Factura B + condIva 5** 로 CAE 를 받았다.
`Cmp_Clase` 는 그 **조회 메서드의 선택적 입력 필터** 설명이지 발급 화이트리스트가 아니다.
→ 표 한 장으로 결론 내지 말 것. 대조군(store 9 실제 발급 기록)이 잡았다.

### codex #2 — 조회 환경 (해결)

reconciliación 은 provider 와 무관하게 늘 SOAP 으로 조회하는데 환경을
`afip_production` 으로 정했다. 그런데 그 값이 발급 환경을 정하는 건 **SOAP 경로뿐**이다 —
게이트웨이는 `production` 을 무시하고 항상 운영으로 발급한다(소스에 `production` 0건,
`homo:false` 하드코딩). 즉 `ws`+`false` 매장은 운영으로 발급하고 homo 를 조회 →
미기록 CAE 를 「없음」으로 오판 → `liberar` → **중복 발급**.

`entorno-afip.ts` 한 곳에서 정하고 reconciliación·인증서 검증이 함께 쓴다 —
따로 두면 「조회는 운영, 인증서는 homo」 모순이 난다.
★ 오늘 노출은 0 이지만 **신규 매장 기본값이 그 조합**(`ws` + `false`)이었다.

### 설정·UX

- `Configuración › Datos de la tienda` 탭 신설 (**alias 수정 자리**).
  허브에 `requiredPrivileged` 역할 게이트를 새로 추가 — 앱 게이트만으로는 vendedor 에게
  보이고 저장에서 403 이 난다. `/perfil` 의 「Editar」 도 같은 결함이라 함께 가렸다
- alias 중복 409 문구 구체화. 기존 사전은 「Ya existe ⟨X⟩ **con ese nombre**」 템플릿이라
  alias 를 넣으면 「alias con ese nombre」 가 된다 → 문장을 통째로 정하는
  `MENSAJES_COMPLETOS` 맵 신설
- **암호 변경은 원래 있었다** — 없던 것은 기능이 아니라 **입구**였다.
  `PUT /auth/change-password` 는 `@Auth()` 무인자(= 인증만 요구)로 처음부터 있었고,
  유일한 입구가 사이드바 아바타 클릭이었다. 메뉴 「Mi perfil」 + 하단 아이콘 2곳으로 노출
  (i18n es/en/ko **세 파일 모두** — 한 곳만 넣으면 다른 언어에서 키가 그대로 뜬다)

---

## 다음 사람이 알아야 할 함정

1. **`ls | wc -l` 과 디렉터리 링크 수는 개수가 아니다.** 인증서 폴더를 「123개 테넌트」로
   두 번 적었는데, 123 은 `ls|wc -l`(폴더+낱개 파일), 115 는 `drwxrwx--- 115` 의 **링크 수**
   (= 2 + 하위 디렉터리 수)였다. 실제는 **113 폴더 · cert+key 짝 109 · Ventago 것 2개**.
   세려면 `find -maxdepth 1 -mindepth 1 -type d`, 「쓸 수 있는 것」은 cert·key 둘 다 있는 것만.
2. **TA 캐시 공유 파일은 `.lastTokens` 다.** 같은 폴더의 `token/TA-*.xml`(2025-02)은
   어느 쪽도 안 쓰는 제3 시스템 잔재다 (종전 메모리가 이걸 공유 캐시로 적어 뒀다 — 틀렸다).
3. **node-forge 는 `serialNumber` 를 shortName 으로 모른다.** `getField({shortName})` → `null`.
   OID `2.5.4.5` 로 넣고 읽어야 한다. AFIP 은 이 필드에 「CUIT <cuit>」 를 요구한다.
4. **jest 「Tests: 0」 은 통과가 아니라 미실행이다.** 돌연변이 시험 중 여러 번 나왔다 —
   컴파일이 깨진 것이다. 컴파일되는 형태로 다시 만들어야 시험이 성립한다.
   (다만 **돌연변이가 컴파일을 깨면 그 자체가 좋은 신호** — 타입 시스템이 이미 막고 있다.
    NC/ND 예약의 「AFIP 호출 뒤로 이동」 이 그 경우였다.)
5. **prettier 바이너리와 eslint 의 prettier 플러그인이 갈린다.** `npx prettier --write` 로
   맞춰도 eslint 가 계속 지적한다. 이 리포에서는 **eslint 쪽이 기준**이다 —
   해당 파일 하나에만 `eslint --fix` 를 건다(전체 `npm run lint` 는 --fix 라 무관한 파일을 쓸어담는다).
6. **기존 spec 이 옛 모델을 전제하고 있을 수 있다.** codex #2 수정으로 cert 테스트 1건이
   실패했는데 **그 실패가 옳았다** — provider 없이 `production=false` 를 homo 로 보던
   전제가 틀린 것이었다.

---

## 남은 것

| 우선순위 | 항목 |
|---|---|
| ★ | **store 6 첫 SOAP 발급 확인** (A=81 / B=123) |
| ~~★~~ | ~~인증서 경로 분리~~ — **완료 2026-09-02** (api `4a86443`). 레거시 마운트 제거까지 같이 끝났다 |
| 하 | `/var/lib/ventago-certs` 가 백업 대상에 없다. 신규 매장이 여기에 키를 만들기 시작하면 넣어야 한다 |
| 중 | `GET /users/:id` 가 본인 확인을 안 한다 (IDOR). 전역 `JwtGlobalGuard` 만 통과하므로 로그인만 하면 남의 id 로 조회된다 |
| 하 | codex 1 — 원본과 NC/ND 의 AFIP 환경이 같다는 보장이 없다 (전표에 환경 컬럼이 없다) |
| 하 | codex 5 — `uq_afip_vouchers_serie` 가 환경·CUIT 를 구분 안 한다 |
| 하 | codex 7 — NC/ND 가 IIBB `provinceId` 스냅샷을 저장 안 한다 |
| 하 | 게이트웨이 `CbtesAsoc` 결함 (`isCreditNote = [3,8,13]`) — **오늘도 ND 원본 참조가 안 나간다.** 별도 리포라 여기서 못 고친다 |

### 「Stock」 매장 = ACE(store 9)

`stores.alias_name='Stock'` 이라 그렇게 부른다(재고 `stocks` 테이블과 헷갈린다).
사용자 확인상 **비활성**이나 **DB 플래그는 `is_active=true`** 이고 최근 90일 판매 13건이 있다.
AFIP 설정은 **homologación 전용**(`coolsyncrohomo1`, 시험 CA)이라 전표 2건은 세무상 무효.
운영 전환하려면 **운영 인증서부터** 필요하다.
반면 **SOAP 경로를 실증한 유일한 기록**이라 대조군으로 값지다.
