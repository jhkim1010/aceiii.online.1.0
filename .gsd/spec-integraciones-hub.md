# SPEC: Integraciones 허브 + Preferencias 도메인 탭 재편
생성일: 2026-07-07

## 목표
외부 서비스 연동(커머스 싱크·결제·메시징)을 `/configuracion/integraciones` 허브 한 곳으로 통합하고,
Preferencias 는 매장 내부 동작 설정만 남겨 Ventas/Precios/Gastos 도메인 탭으로 재편한다.

## 배경 및 컨텍스트
- WooCommerce 설정: `/sucursales/[id]/web` (WpConfigTab) — 지점 단위, 유지하되 허브에서 진입
- store-level 엔드포인트 존재: `GET /integrations/wp/channels`, `GET /integrations/tiendanube/channels`, `GET /whatsapp/store-config`
- TiendaNube: 백엔드 어댑터/OAuth 존재, 프론트 UI 없음 → 상태만 표시, 설정은 Próximamente
- EmpreTienda/Signo/MercadoLibre(싱크)/Telegram: 미구현 → Próximamente 카드
- Mercadopago: `/configuracion/mercadopago` 존재 → 허브 "Pagos" 섹션에서 링크
- WhatsApp: `/configuracion/whatsapp` 존재, connected = store-config.representative.whatsappPhone
- Preferencias 현재 6개 뷰 혼재 (3분할 드래그 패널): CategoriasGastos / Restaurante / Mercadopago / WhatsApp / Inventario / PriceTypes

## 기술 스택
- Next.js 13 Pages Router + MUI 5, next/dynamic ssr:false (코드 스플리팅 규약)
- 상태 조회: Promise.all 병렬 (순차 호출 금지 규약)
- DB 변경 없음

## 최종 구조
### /configuracion/integraciones (신설)
- Canales de venta: WooCommerce(상태+지점선택 진입) / TiendaNube(상태만) / EmpreTienda / MercadoLibre / Signo (Próximamente)
- Pagos: Mercadopago (→ /configuracion/mercadopago)
- Mensajería: WhatsApp(상태, → /configuracion/whatsapp) / Telegram (Próximamente)

### /configuracion/preferencias (재편)
- 탭 Ventas: RestauranteConfigView + InventarioConfigView
- 탭 Precios: PriceTypesList
- 탭 Gastos: CategoriasGastosTreeView
- 제거: Mercadopago/WhatsApp 패널 (허브로 이전), 3분할 드래그 레이아웃
- 마지막 활성 탭 localStorage 유지 (`preferencias-tab`)

## 태스크 목록
- [ ] TASK-1: `src/views/configuracion/integraciones/IntegracionesHubView.tsx` 신규
- [ ] TASK-2: `src/pages/configuracion/integraciones/index.tsx` 신규 (dynamic, acl configuracion)
- [ ] TASK-3: `src/pages/configuracion/preferencias/index.tsx` 탭 구조로 재작성
- [ ] TASK-4: navigation configChildrenBase 에 Integraciones 추가 (Preferencias 다음)
- [ ] TASK-5: locales 3개 파일에 nav_integraciones 추가
- [ ] TASK-6: iconify 번들에 plug-connected/brand-wordpress/brand-telegram/shopping-cart/receipt/package 추가 + 재생성
- [ ] TASK-7: ESLint 검증

## 완료 기준
- ESLint 오류 0개
- 허브 상태 조회는 Promise.all 3건 병렬, 실패 시 카드 degrade (에러 핸들링 필수)
- 기존 경로(/configuracion/whatsapp, /configuracion/mercadopago, /sucursales/[id]/web) 접근성 유지

## 금지사항 / 주의사항
- 백엔드 변경 금지
- WpConfigTab / 기존 뷰 컴포넌트 내부 수정 금지 (임베드만 변경)
- pageSize/캐시 규약 준수, useEffect 순차 호출 금지
