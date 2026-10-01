# 핸드오프 2026-09-30 (밤) — AFIP 매장별 superadmin 설정 · 가격 원칙 · 목록 순서 · 잡건

> 앞 문서: `HANDOFF-2026-09-30-tarde.md` (오후)

## 1. 운영에 나간 것 (전부 빌드·컨테이너 확인)
| 내용 | 커밋 | 빌드 |
|---|---|---|
| POS: descuento/recargo/transporte 후 커서 항상 Cantidad | app `464f5d88` | #885 |
| MinIO `POST /minio`: 이름 `_<store 5자리>` + 충돌 시 `(n)` + **조건부 PUT(If-None-Match)** + 비공개 확장자 400 · 프론트 원본명 폴백 제거 | api `e1fc78a9` · app `1e4b1402` | #1020/#886 |
| 앱 jest `pos-precio-lista-igual-al-cobro` 낡은 시험 수정(levelFor) | app `f65f1959` | #887 |
| Costo por variación: **새 변형 가격 = 원가식** (경로 6 + 재부착 2) `alinearVariantesNuevasAlCosto` | api `454504b3` | #1021 |
| Costo por variación: **손 가격 변경 → ERR-COSTO-013** (11 경로, 같은 값은 통과, 임포트는 행 오류) | api `0cee1815` | #1022 |
| 새 상품 입력 단계에서 Costo por variación 체크 가능 (`pedidoCostoNuevo`) | app `1c167d37` | #888 |
| 상품: USD 선택 시 cotización 없으면 대화상자 · 있으면 「Dólar actual · cambiar」 · 오른쪽 빈 배너 제거 | app `4f6dc408` | #889 |
| Vendedores: 정렬 name,last_name,id + 스위치 행만 갱신 | api `b2ac4c80` · app `8450101e` | #1024/#890 |
| 목록 정렬 고정(Tiendas·Registros·StoreApps·CrudService.findAll·gastos 트리) + StoreApps 스피너 첫 로드만 | api `67a2579e` · app `927c8e88` | #1025/#891 |
| Facturación: 「sin emisor」 경고가 스위치/Configuración del emisor 로 이동 | app `8bbaeacb` | #892 |
| **superadmin 이 매장별 AFIP 설정**(`tiendaDestino`, 11 엔드포인트 `?storeId=`) · **GET /afip/cert/csr「Ver CSR」**(같은 키) · compose `AFIP_CERTS_DIR_VENTAGO=/app/certificates` | api `d0c5f404` | #1026 |
| 관리자 매장 상세 「Facturación de esta tienda (AFIP)」(superadmin 전용, `key={id}`) · 인증서 카드 Ver/Descartar/전용폴더/Activar | app `3987205d` | #893 |

## 2. 측정으로 확인한 사실 (재발 방지)
- **경합 ①(원가 저장 중 새 변형)은 원래 막혀 있었다**: madre `FOR UPDATE`(원가 저장) × `FOR KEY SHARE`(변형 INSERT 의 FK). advisory 추가는 결과 동일 → 제거. itest `variante-nueva` 가 이 동작을 고정(madre 잠금 제거 돌연변이 → 실패).
- MinIO RELEASE.2025-06-13 + minio-js 8: `If-None-Match:*` 동시 5건 → 1 성공 / 4 `PreconditionFailed` (서버 임시 컨테이너로 실측).
- 운영 Ventago DB: 매장 21 · AFIP 발행자 3 (6 coolsistema soap·prod / 9 ACE soap·homo / 25 Charo ws). 「300여 매장」은 이 DB 에 없다(cool-invoice 등).
- 인증서 루트 `/app/certificates` = 호스트 `/var/lib/ventago-certs`(Ventago 전용). `coolsistema` 만 `jenkins/workspace/certificados/coolsistema` 중첩 마운트(공유).
- 「Costo por variación」 켠 상품 운영 0건.

## 3. 남은 일 — 우선순위
1. **coolsistema 인증서 10/20 무렵 만료** (cert 2024-10-20). 오늘 9/30 21:09 ART 에 공유 폴더에 CSR 생성됨(`key.new` 가 공유 폴더 안) → **그 CSR 로 .crt 올리면 안 됨**(cool-invoice 인증서까지 교체).
   절차: superadmin › 매장 6 상세 › Descartar y generar otro(→ `ventago_st6`) → ARCA Agregar alias·CSR → .crt → 관계 wsfe + ws_sr_constancia_inscripcion → Subir → **Activar**.
2. **Admin Dashboard 맨 윗줄 지표**(사용자 결정 완료, 미구현):
   - 7개: 당일 총 venta · 총 현금(efectivo) · venta 건수 · prendas · movidos **장수(횟수)** · 오늘 comprobantes **건수·금액·neto·IVA** · 이번 달 comprobantes 누계 금액
   - 기존 6카드는 둘째 줄로(VENTAS HOY 는 대체) · **선택 지점 따라감** → 대시보드엔 선택기 없음: 새 줄에 지점 선택(Todas/지점), 초기값 BranchContext `selectedBranchId`
   - 규칙: 매장 tz `DATE(sale_date AT TIME ZONE tz)`, venta 는 `getDailyStats`(sales.service.ts:1082) 기준(anulación ±, `credit_payment_id IS NULL`), 지점 `COALESCE(s.branch_id, bx.branch_id, u.branch_id)`, 현금 `sale_payment_methods`+`payment_methods.slug='efectivo'`, movidos = `activity_type='movido'` (origin OR target), comprobantes = `afip_vouchers` · 날짜 `COALESCE(cbte_fch, created_at AT TIME ZONE tz)` · `entorno` 필터(reportes-arca.service.ts:145) · NC 음수 · neto/IVA = `computeNetoIva`(code-maps.ts) + `BASE_POR_ALICUOTA`(reportes-arca.service.ts:34 — 순수 모듈로 옮겨 공유할 것)
   - ★ 기존 VENTAS HOY(dashboard-admin.service.ts:517)는 **UTC 오늘**이다(21시 이후 판매가 다음날) — 같이 고칠 것
3. AFIP 카드 잔여: 새로고침하면 「Activar」 버튼 사라짐(GET /afip/cert 가 「업로드됨·미활성」 상태를 안 줌) · 「revertir」 버튼 없음.
4. Costo por variación 잔여: Deshacer(revert)는 가드 없음(의도). `/prices` CRUD 는 테넌트 범위가 `findOne` 훅 의존.
5. 이전 문서 잔여: Express 5 배열 쿼리 전수 조사 · superadmin 전용 설정 페이지 · APK Drive 업로드 · Sager 발행자 미등록(이제 superadmin 화면에서 가능).

## 4. 환경 메모
- CODEX: `codex exec --sandbox read-only "$P" </dev/null > out` (diff 를 프롬프트에 직접). 자동 훅 기준선은 오래됨.
- 커밋 게이트는 `git add` 와 `git commit` 을 **같은 명령에 두면 거절**한다 — 따로 실행.
- itest: `npx jest --config ./test/itest/jest-itest.json --runInBand <name> --forceExit --testTimeout=60000` (동시성 시험은 `finally` 로 tx 정리 — 안 하면 돌연변이 때 멈춤).
- 로컬 DB 시험 흔적: 매장 `ZZ-VARIANTE-NUEVA` 는 itest 가 매번 지우고 다시 만든다.
