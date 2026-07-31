---
id: 002
title: P69-02 R1 소켓 소비자 자격증명 배선 (POS 4 + print-agent)
priority: high
created_at: 2026-07-31T20:16:19.807Z
---

## Task
PLAN: .planning/phases/69-tenant-isolation-security-hardening/69-02-PLAN.md

repo: ventago-app(서브모듈) + print-agent. api-ventago 는 건드리지 않는다.
wave 1. 69-01 과 파일 교집합 0 — 병렬 가능.
★배포 순서: 이 작업(app/agent)이 69-01(api)보다 먼저 배포돼야 한다. 역전 시 유예 10초 뒤 팀채팅·MP 승인·프린터 상태가 조용히 멈춘다.
