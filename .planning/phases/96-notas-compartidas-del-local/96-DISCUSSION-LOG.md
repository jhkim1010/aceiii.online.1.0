# Phase 96: Notas compartidas del local - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-28
**Phase:** 96-notas-compartidas-del-local
**Areas discussed:** Team Chat 과의 관계, 대상과 작성 권한, 읽음 확인과 알림, 반응·답글과 nota 수명 (+ 세부 확인)

---

## Team Chat 과의 관계

| Option | Description | Selected |
|--------|-------------|----------|
| 별개 기능 | 테이블·화면 별도, 소켓·사용자 목록 재사용 | ✓ |
| Notas 가 Team Chat 대체 | 하나로 합침 | |
| Team Chat 확장 | 채팅 메시지에 중요 표시·반응·답글 | |

| 화면 형태 | | |
|---|---|---|
| 게시판 카드 목록 + 탭 | | |
| 좌우 분할(받은편지함형) | | |
| 목업을 보고 정하겠다 | | ✓ |

## 대상과 작성 권한

- 전체 발송: **권한으로 제어(기본 admin)** ✓ / 누구나 / 관리자만(고정)
- 대상 범위: **Todos / 여러 명 선택** ✓ / Todos / 1명만 / Todos / 지점 / 여러 명
- 개인 nota 가시성: **보낸 사람과 받는 사람만** ✓ / 관리자는 전부
- 형식: **제목 + 본문 + 중요도** ✓ / 본문만 / 제목 + 본문 + 카테고리

## 읽음 확인과 알림

- 알림: **배지 + 실시간 토스트** ✓ / 배지만 / 배지+토스트, Urgente 모달
- POS 화면: **배지만** ✓ / 다른 화면과 같게
- 읽음 확인 표시: **읽은/안 읽은 사람 목록** ✓ / 숫자만 / 표시 안 함
- 읽음 기준: **열면 읽음, Importante·Urgente 는 Entendido** ✓ / 목록에 보이면 읽음 / 항상 버튼

## 반응·답글과 nota 수명

- 반응: **고정 5개** ✓ / 자유 이모지 / 👍 하나
- 답글: **한 단계, 볼 수 있는 사람 전원** ✓ / 한 단계, 작성자만 / 다단계
- 수정·삭제: **editado 표시 + 보관처리** ✓ / 수정 불가, 삭제만 / 둘 다 불가
- 부가 기능(복수): **상단 고정 ✓ · 첨부 ✓ · 만료일 ✓ · 검색 ✓**

## 세부 확인

- 신규 직원의 과거 Todos 조회: **볼 수 있음** ✓ / 발송 시점 사용자만
- 고정 권한: **Todos 발송 권한과 같음** ✓ / 별도 권한
- 만료 후: **목록에서 빠지고 Vencidas 필터** ✓ / 보관과 같게
- 첨부: **사진 + PDF, 최대 5개** ✓ / 사진만 / 모든 파일

## Claude's Discretion

테이블 설계, 인덱스, 소켓 이벤트 이름, SWR 키, 권한 slug 이름, 토스트 컴포넌트.

## Deferred Ideas

지점 단위 발송, 카테고리, 다단계 스레드, 자유 이모지.
