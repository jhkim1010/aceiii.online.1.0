# Phase 99 — CONTEXT (결정 2026-10-05)

근거 분석: `.planning/ANALISIS-2026-10-05-menu-estructura.md` · 목업 `.planning/sketches/menu-propuesta.png`.
근본 원인: 메뉴가 다섯 곳(DB 시드 · menuRegistry 주입 · Configuración 허브 TABS · 화면 내 링크 · superadmin/agent 하드코딩)에서
따로 만들어지고 서로 대조하는 검사가 없다. 137 라우트 중 30+ 가 어떤 메뉴에서도 도달 불가.

## Decisions (LOCKED, 사용자 2026-10-05)
- **D-01** 지원 토큰(CoolSistema) 과 「Acceso de Ventago」 를 **합칠 수 있으면 합친다** — 먼저 가능 여부를 코드로 확인
  (지원팀이 Acceso 방식으로 일할 수 있는지: 범위·유효시간·사용량/과금). 불가하면 근거와 함께 보고.
- **D-02** 판매원 앱·출고 앱·시계 연결 등 기기 연결을 **Configuración › Dispositivos 탭 하나로 모은다**.
- **D-03** Carpetas compartidas **살린다** — 설정 화면은 Configuración, 직원용은 Herramientas. Google 서비스 계정 설정·실제 Drive 시험 포함.
- **D-04** Dashboard ventas 를 메뉴에 **다시 노출**.
- **D-05** ClienteVista·CodigoVista **현재 위치 유지** (이름도 유지).
- **D-06** 보고서 옛 주소 `/reportes/*` 17개 **유지(삭제 안 함)** · Reportes v2 의 깨진 legacyHref 3개(enviado·stock-vistas·season-turnover) 수정 ·
  `/reportes/asistencia`(출근·가불 승인, 운영 사용 중)를 **Reportes 목록에 추가**.
- **D-07** 표시명은 「**Control de envíos**」.
- **D-08** 메뉴 그룹 순서 **Admin 맨 위 유지**.
- **D-09** 분석 문서의 나머지 수정(허브 탭 게이트를 페이지 게이트와 같은 상수로, menuRegistry 주입 항목에 권한 필터, 지원 토큰 API admin 전용,
  재발 방지 시험 2개 — 허브 「키→화면」 고정 · 라우트 진입점 등록 목록 + 대조군)은 분석 문서 권고대로.

## 이미 끝난 것 (2026-10-05, 이 Phase 전)
- Configuración › Avanzado 「Token de soporte」 복원(353ab400) · 탭 내 임베드(ba9c7b1b) · 「Relojes」 탭(8744399b) · /admin/generar-token admin 전용(a734bd68).

## 제약
- 낮 08–16시(AR) 운영 반영은 활동 사용자 ≤5 일 때만(CLAUDE.md). **사이드바 변경은 structure 시드 먼저 → 코드**(memory sidebar-derives-from-structure-seed-first), 운영 DML 은 SQL+영향 행 승인 후.
- 미확인 보안 항목: `/admin/permisos` 가 부르는 `PUT/POST /functions` 서버 가드 — 이 Phase 에서 확인.
