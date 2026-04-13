# Phase 17: Portal de Talleres - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-13
**Phase:** 17-portal-de-talleres-aviso
**Areas discussed:** 포털 형태, 기능 범위, 인증, 멀티매장, 알림

---

## 포털 형태

| Option | Description | Selected |
|--------|-------------|----------|
| Ventago 내 별도 로그인 | 기존 인증 시스템 활용, 제한된 화면만 접근 | |
| 토큰 기반 링크 | 로그인 없이 토큰 URL로 접속 | |
| 독립 앱/사이트 | 별도 도메인의 독립 앱 | |

**User's choice:** Flutter 독립 앱 — 다른 자료 접근 차단, 한 업체가 여러 매장 물건 한눈에 처리
**Notes:** 완전 분리된 모바일 앱. 한 vendor가 여러 store와 거래하는 케이스 지원 필수

---

## 기능 범위

| Option | Description | Selected |
|--------|-------------|----------|
| 진행현황 확인 | 발송된 로트/공정 목록 + 수량 + 납기 | ✓ |
| 수령 확인 | 완료/부분완료 마킹 → 매장 알림 | ✓ |
| 알림 수신 | 새 발송, 납기 임박, 정산 완료 등 | ✓ |
| 정산 이력 확인 | 정산 금액/상태 읽기 전용 | ✓ |

**User's choice:** 4가지 모두 선택
**Notes:** 모든 기능 포함

---

## 인증

| Option | Description | Selected |
|--------|-------------|----------|
| 전화번호+PIN (추천) | 매장 관리자가 PIN 발급 | ✓ |
| 아이디/비밀번호 | 별도 계정 체계 | |
| Magic Link | 일회용 링크 | |

**User's choice:** 전화번호+PIN
**Notes:** 간단한 인증. 매장 관리자가 발급

---

## 멀티매장

| Option | Description | Selected |
|--------|-------------|----------|
| 매장별 탭 (추천) | 하단 탭으로 매장 전환 | ✓ |
| 통합 뷰 | 모든 매장 한 리스트 | |
| 매장 선택 후 진입 | 선택 화면 거쳐서 진입 | |

**User's choice:** 매장별 탭
**Notes:** 하단 탭바로 자유 전환

---

## 알림

| Option | Description | Selected |
|--------|-------------|----------|
| 앱 내 알림만 (추천) | 미읽음 배지, 푸시 없음 | ✓ |
| 푸시 알림 포함 | FCM 푸시 | |
| WhatsApp/SMS | 외부 서비스 | |

**User's choice:** 앱 내 알림만
**Notes:** 푸시는 추후 별도 phase

---

## Claude's Discretion

- Flutter 프로젝트 구조, UI 디자인
- 백엔드 vendor auth 세부 구현
- 알림 DB 테이블, PIN 암호화

## Deferred Ideas

- 푸시 알림 (FCM)
- 채팅/메시지
- 사진 첨부
- 오프라인 모드
