# SPEC: 매장 관리자용 모바일 앱 (tienda-admin-app)
생성일: 2026-07-23

## 목표
매장 관리자(store_owner/store_admin/gerente/admin)용 Flutter 폰 앱. superadmin 앱
(ventago-admin-app)의 세션 뼈대를 계승하고, 웹앱에만 있던 대시보드·Caja·보고서·권한을
폰 화면으로 재구성한다. 목업: mockups/tienda-admin-mockup.html (아티팩트 tienda-admin-app-mockup).

## 배경/아키텍처 결정
- 복제 기반 스캐폴딩: ventago-admin-app → tienda-admin-app (rsync, build/캐시 제외).
  core/(theme·dio·secure_storage·biometric·session_signal), _AuthGate, android manifest
  (INTERNET 권한), macOS keychain 우회, local_auth용 FlutterFragmentActivity 그대로 승계.
- 식별자: applicationId=com.coolsistema.tienda_admin_app (superadmin과 동시 설치),
  pubspec name=tienda_admin_app, label="Admin de Tienda". namespace/kotlin 패키지는
  ventago_admin_app 유지(R클래스 안전). 구 console 화면은 _reference_console/ 로 이동.
- ★인증: 매장 엔드포인트는 JwtAuthGuard(+역할/권한)만 사용 → SessionGuard/x-session-token
  불필요(백엔드 감사로 확정). dio 는 JWT-only 유지. /auth/me 가 storeId·storeName·
  aliasName·structure·cashRegister 반환 → AuthUser 확장. 역할 게이트 isStoreManager.
- pool 안전: dashboards/cash-register 는 storeId 를 토큰에서 서버가 스코핑(파라미터 X).
  Caja 요약은 열린 카하(소수)만 resume 병렬 조회. PG 문자열 숫자 방어(asInt/asNum).

## 기술 스택
- Flutter 3.11 + Riverpod 2.5 + dio 5.4 + flutter_secure_storage 9 + local_auth 2 + intl.
- ESLint 해당 없음 → 검증 = `flutter pub get` + `dart analyze lib` (러너 잡 tienda-analyze).

## 태스크 (Wave 1 — 완료)
- [x] W1-1: 앱 복제 + 식별자 정리 (rsync, sed appId/label/name, console 이동)
- [x] W1-2: core dio JWT-only 코멘트 정리 (x-session-token 없음)
- [x] W1-3: auth 확장 — AuthUser storeId/storeName, isStoreManager 게이트, /me 토큰 갱신
- [x] W1-4: main.dart(TiendaAdminApp) + login_screen("Admin de Tienda") + nav_state 5탭
- [x] W1-5: app_shell — 하단 5탭(Panel·Caja·Reportes·Usuarios·Actividad) + 매장명 표시
- [x] W1-6: shared/format.dart (asInt/asNum, money es_AR 0소수, pct, todayStr)
- [x] W1-7: Panel — /dashboards/sales/summary KPI + 주간 스파크라인 + Caja 실시간 카드
- [x] W1-8: Caja(실시간) — /cash-register 오늘목록 + 열린카하 resume saldo + 상태칩
- [x] W1-9: Caja 상세 — /cash-register/:id/resume totals 분해 + /box-operation 거래
- [x] W1-10: Actividad — /dashboards/sales/last-sales 최근판매 피드(실데이터)
- [x] W1-11: Reportes 허브(정적 카탈로그) + Usuarios 자리표시자
- [x] W1-12: 검증 — dart analyze lib → "No issues found!"

## 태스크 (Wave 2 — 예정)
- [ ] W2-1: Usuarios/Permisos — GET /users/store/:storeId + GET /role → 역할 카드
- [ ] W2-2: 권한 편집 — GET /functions/structure + /role-functions/:roleId,
             트리(Recurso CRUD 칩 / Business Action 토글), 저장 PUT /role-functions/bulk-actions/:roleId
- [ ] W2-3: Reportes 상세 — /reports/breve-venta-report, /reports/sales-report 등 연결(기간 필터)
- [ ] W2-4: APK 빌드(러너 flutter build apk) + 설치본 Dropbox 복사 + 폰 실기 로그인/지문 검증
- [ ] W2-5: (선택) CI 워크플로 build-tienda-admin-app.yml + Descargas 카드

## 완료 기준
- dart analyze 0 issue (Wave 1 충족). 폰에서 로그인/지문 → Panel/Caja 실데이터 표시.

## 금지/주의
- x-session-token 추가 금지(불필요). dio JWT-only 유지.
- _reference_console/ 는 참조용 — lib 밖이라 컴파일 제외. 삭제는 사용자 판단.
- 러너 flutter 잡은 zsh -ilc 필수(bash는 flutter PATH 못잡음).

## Wave 2 (완료·2026-07-23)
- [x] W2-1: Usuarios 화면 — Roles/Usuarios 세그먼트. GET /role?storeId(userRols), GET /users/store/:storeId(roles[]).
- [x] W2-2: 권한 편집(permissions_editor) — GET /functions/structure(App→Módulo→Función, resourceKey camelCase) + GET /role-functions/:roleId(roleFunctionActions[].action). resourceKey 있으면 CRUD 칩(slug 접두사→create/read/update/delete, 버킷 전체적용), 없으면 Business Action 토글(=4개 전부). 저장 PUT /role-functions/bulk-actions/:roleId {data:[{functionId,actions[]}]} — ★전체교체(빠진 functionId 삭제)라 actions>0 전부 전송.
- [x] W2-3: Reportes 상세(reporte_detalle) — Breve Venta·Ventas·Vendedor 연결. GET /reports/<slug> {storeId(명시 필수),startDate,endDate=YYYY-MM-DD HH:mm:ss}. 응답 {data:[]}. sales-report totalAmount=DECIMAL 문자열→asNum. 기간 세그먼트 Hoy/7días/Mes. 나머지 리포트는 안내.
- [x] W2-4: 검증 dart analyze lib=No issues. APK 51.6MB 재빌드 + Dropbox 복사(tienda-apk-w2/tienda-apk-dropbox).
- 잔여: 폰 실기(권한 저장/리포트 실데이터) 확인, 나머지 리포트 확장, (선택) CI.

## Wave 3 (완료·2026-07-24) — 리포트 5종 추가
- [x] Gastos·Stocks·Alertas·Provincia·Cheques 연결(총 8종). 4종은 {data:[]}, ★provincia-dashboard 만 {totals,rows}(예외). 화폐필드는 서비스가 Number() 강제→숫자지만 asNum 방어.
- Stocks/Alertas 는 현재고 스냅샷 → 기간 세그먼트 없음. Alertas estado='Sin Stock'(red)/'Bajo Stock'(amber) 배지. Stocks 는 storeId 미스코프(백엔드 filter 만 사용) 참고.
- [x] dart analyze=No issues. APK 51.6MB 재빌드+Dropbox 복사(tienda-apk-w3).
- 리포트 허브 8장 전부 활성. 잔여: 폰 실기 확인, (선택)CI.

## Wave 4 (완료·2026-07-24) — 전체 마무리
- [x] 리포트 8종 추가 → 허브 16종 전부 상세 연결(items/fallados/corregido/facturacion/clientes-credito/ingreso/movidos/reservado). 전부 {data:[]}, ★Productos price 만 DECIMAL 문자열→asNum. clientes-credito 는 기간 없음(스냅샷).
- [x] Caja 마감: caja_detail 하단 "Cerrar caja" 버튼(열린 카하만) + 확인 다이얼로그 → POST /cash-register/close/:id → overview/resume invalidate + pop.
- [x] 사용자 CRUD: user_form_screen(생성/수정). POST /users/admin-create(role/username 처리), PUT /users/:id(부분·password 선택·role 교체), DELETE /users/:id(soft→inactive). 지점=GET /branch(배열). usuarios_screen Users 에 "Nuevo usuario"+탭편집.
- [x] CI: .github/workflows/build-tienda-admin-app.yml(태그 tienda-admin-app-v*, Android APK→jhkim1010/ventago-downloads, RELEASE_REPO_TOKEN). ※device_commit 은 .github 보호 → device_bash 로 작성.
- [x] Descargas 카드: ventago-app/src/pages/herramientas/print-agent/index.tsx programs[] 맨앞에 tienda-admin-app 항목(fileName VentaGO-Tienda-Admin.apk).
- [x] dart analyze lib=No issues. APK 52.3MB 재빌드+Dropbox 복사.
- ★잔여(사용자 트리거): git commit+push(tienda-admin-app+workflow→root main), 태그 tienda-admin-app-v1.0.0 push(CI 트리거), ventago-app Descargas push(프론트 배포). 프로덕션 배포라 사용자 승인 후 실행.
