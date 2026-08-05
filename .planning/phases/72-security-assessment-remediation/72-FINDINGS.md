# Phase 72 — 보안 점검 보고서 대조 결과 (2026-08-05)

원본: `docs/security_assessment_aceiii_online.pdf` (외부 정적·구성 검토, 9건)

계획서로 옮기기 전에 **전부 코드·운영으로 확인**했다. 결론:
**8건 실재 · 1건 재현 실패 · 위험도 판단은 3건에서 보고서와 갈린다.**

---

## 실재하는 것

### C1. 무인증 Edge API — 사실

`edge-agent/src/index.js:42` — `app.listen(cfg.port, ...)`. **host 인자가 없어 전 인터페이스에 바인딩**된다.
`edge-agent/src/server.js:37~39` — `Access-Control-Allow-Origin: *`.

라우트 **10개 전부 인증이 없다**:
```
/api/health · /api/edge/status · /api/edge/sync-now
/api/offline/table/:key · /api/offline/product-lookup · /api/offline/sales
/api/offline/print/temp · /api/offline/print/barcode
/api/offline/auth/login · /api/offline/outbox
```
`GET /api/offline/table/:key` 가 미러를 그대로 반환하므로 `users` 도 나온다 → H1 과 결합된다.

### C2. 판매자 신원 위변조 — 사실. **코드가 스스로 인정한다**

`edge-agent/src/server.js:15~17` 주석 원문:
```
// JWT payload 디코드 (서명 검증 없음 — LAN 오프라인 한정 신원 힌트)
// ⚠ 보안 메모: edge 는 JWT secret 이 없어 서명 검증 불가. 오프라인 판매의 userId 는
// push 시 서버 원장에 기록되어 사후 감사 가능. Wave C 에서 HMAC 강화 예정.
```
알고 남긴 부채다. `:179` 에서 그 payload 로 신원을 정한다.

### H1. 비밀번호 해시 미러 + 무제한 로그인 시도 — 사실

`server.js:311~331` — `mirror_rows` 의 `data->>'password'`(bcrypt 해시)로 `bcrypt.compare`.
rate limit·잠금·지연이 **없다.** 실패 시 `log.warn('[auth] login FAIL — email=${email} …')` 로
이메일이 로그에 남는다(보고서의 Medium «로그인 실패 이메일» 도 여기서 확인됨).

C1 과 결합하면 **무인증으로 해시 전량 취득 → 오프라인 크래킹**이 성립한다.

### M. 보안 헤더 부재 — 사실 (운영 실측)

`ventago-app/next.config.js` 에 `headers()` **없음**(0건).
운영 실측:
```
curl -sI https://ventago.coolsistema.com
→ HTTP/2 307   (CSP·HSTS·X-Frame-Options·Referrer-Policy·Permissions-Policy 전무)
```
보고서는 "프록시에서 설정되는지 추가 검증 필요"라고 했는데, **검증 결과 프록시에도 없다.**

### M. 관리자 앱 원문 비밀번호 보존 — 사실

`ventago-admin-app/lib/core/storage/secure_storage.dart:10` — `savedPass = 'admin_saved_pass'`
`auth_controller.dart:123` — `_storage.write(StorageKeys.savedPass, password)` (원문)
`auth_controller.dart:151` — `logout()` 은 **토큰만** 지운다. 주석에 의도 명시:
> 로그아웃: 세션 토큰만 지우고 자격증명은 유지 → 다음에 지문으로 재로그인 가능.

macOS 는 `useDataProtectionKeyChain: false`. 이유가 주석에 있다 — 비-sandbox 빌드에서
entitlement 없이 data-protection keychain 쓰기가 `errSecMissingEntitlement(-34018)` 로 실패해 회피한 것.
**의도적 우회이지 실수가 아니다.** 그래도 보호 수준이 낮아진 건 사실이다.

### M. 오류 응답의 내부 예외 노출 — 부분 확인

edge 로그인 실패 이메일 로깅은 확인(H1 항목). API 전반의 예외 메시지 노출은 표본만 확인했다.
전수 조사는 72-02 작업 범위에 포함한다.

---

## 이미 해결된 것

### C3. 저장소 하드코딩 DB 비밀번호 — **오늘 해결됨**

보고서 작성 시점 기준으로는 사실이었다. 같은 날(2026-08-05) 처리했다:
- 평문 제거: 루트 20파일 + api-ventago 6파일 (커밋 `089ca0c`, `51fe3aa`)
- **비밀번호 회전: PG18(5434) + PG10(5433) 양쪽** (커밋 `e35338a`)

현재 저장소 스캔 잔존 **0건**. 구 비밀번호 인증 거부 확인됨.

**남은 것:** 보고서의 «Git 이력에서도 제거» 는 하지 않았다. 회전으로 값이 무효화돼 실익이 크게
줄었고, 서브모듈 3개가 물린 저장소에서 이력 재작성은 협업자 클론을 전부 깨뜨린다.
비용 대비 이득이 맞지 않아 **범위 밖**으로 둔다(판단 근거를 남긴다).

---

## 재현되지 않은 것

### M. 디자인 편집 토큰이 URL 쿼리에 포함 — **확인 필요**

`?token=` / `&token=` / `router.query.token` 패턴을 `ventago-app/src`, `api-ventago/src`,
`tienda-admin-app` 전체에서 찾았으나 **해당 코드를 발견하지 못했다.**
Phase 61(tienda-online-editor)은 계획 디렉터리만 있고 구현 흔적이 없다.

보고서가 어느 파일을 본 것인지 불명확하다. **근거 없이 계획서에 넣지 않는다** —
원 보고서 작성자에게 파일·줄 위치를 확인한 뒤 판단한다.

---

## 위험도 판단 — 보고서와 갈리는 지점 3건

### ① Edge 3건(C1·C2·H1)은 «즉시 조치» 가 아니다 — **배포 게이트**다

`edge-agent` 는 **어디에도 배포돼 있지 않다**:
- 운영 서버 컨테이너 없음 (`docker ps -a | grep edge` → 없음)
- `.github/workflows/` 에 **빌드 워크플로 없음** (print-agent·zebra-agent 는 있다)
- 최근 커밋이 Wave B 개발분 (`26ee432`, `7bda05f`)

즉 **활성 침해 경로가 아니다.** 성격은 "지금 뚫려 있다"가 아니라
"이 상태로 배포하면 뚫린다"이다. 대응 시급성이 아니라 **배포 차단 조건**으로 다뤄야 한다.

### ② Next.js CVE 직접 영향 없음 — High 는 과하다

`next: 13.3.2` 가 취약 버전인 것은 사실이다. 다만 해당 CVE 는 **middleware 를 통한 인가 우회**인데,
이 프로젝트에는 `middleware.ts` / `src/middleware.ts` **파일 자체가 없다.**
업데이트는 해야 하지만 "알려진 우회가 지금 성립한다"는 아니다.

### ③ C3 는 해결 완료 — 보고서 요약의 «Critical 3건» 은 현재 **2건**(둘 다 미배포 edge)

---

## 정리

| 원 위험도 | 항목 | 현재 판단 |
|---|---|---|
| Critical | 무인증 Edge API | **배포 게이트** (미배포) |
| Critical | 오프라인 신원 위변조 | **배포 게이트** (미배포, 코드 주석이 인정) |
| Critical | 하드코딩 DB 자격증명 | **해결 완료** (2026-08-05 제거 + 회전) |
| High | 해시 미러 + 무제한 로그인 | **배포 게이트** (미배포) |
| High | Next.js 13.3.2 | **Medium 상당** (middleware 미사용) |
| Medium | URL 토큰 | **확인 필요** (재현 실패) |
| Medium | 관리자앱 원문 비밀번호 | 사실 |
| Medium | 오류/로그 노출 | 사실(부분 확인) |
| Medium | 보안 헤더 부재 | 사실 (운영 실측으로 확정) |
