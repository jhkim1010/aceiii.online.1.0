---
phase: 11
plan: 05
subsystem: ci+frontend+packaging
tags: [github-actions, electron-builder, releases, monorepo, npm-workspaces, print-agent]
requires: [11-04]
provides:
  - GitHub Actions workflow build-print-agent.yml (Windows .exe + macOS .dmg cross-build on tag push)
  - print-agent gitlink → regular directory promotion (CI checkout enablement)
  - print-agent/package.json artifactName fixed file names + publish:null
  - ventago-app/src/config/printAgent.ts Releases latest/download URL constants
  - PrinterConfigTab 3 download buttons (Windows / Mac Intel / Mac Apple Silicon) + Releases page link
  - print-agent/RELEASE.md release procedure documentation
affects:
  - .github/workflows
  - print-agent (gitlink → tracked files)
  - print-agent/package.json
  - ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx
  - ventago-app/src/config
tech-stack:
  added: [GitHub Actions, softprops/action-gh-release@v2]
  patterns:
    - tag-triggered cross-OS build (windows-latest + macos-latest matrix-by-job)
    - npm workspaces aware CI (root npm ci + npm run -w print-agent)
    - electron-builder install-app-deps for native module rebuild (escpos-usb/libusb)
    - releases/latest/download permanent URL pattern (version-less artifactName)
    - fail_on_unmatched_files for silent-failure prevention
key-files:
  created:
    - .github/workflows/build-print-agent.yml
    - ventago-app/src/config/printAgent.ts
    - print-agent/RELEASE.md
  modified:
    - print-agent/package.json
    - ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx
    - print-agent (promoted from gitlink to regular directory — 16 files now tracked directly)
decisions:
  - print-agent를 서브모듈이 아닌 root repo의 일반 디렉토리로 통합 — 외부 remote가 없어 서브모듈 유지 이유 부재, CI checkout 단순화
  - artifactName을 버전 없는 고정 이름으로 지정 — releases/latest/download/ 영구 URL 패턴 사용 (프론트 다운로드 링크 동적 버전 쿼리 불필요)
  - root npm ci + -w print-agent 패턴 — 모노레포 워크스페이스 부모 추적 유지, 중첩 cd 회피
  - electron-builder install-app-deps을 워크플로우 명시 단계로 분리 — postinstall 의존 제거 (로컬 개발 시 불필요한 재빌드 방지)
  - mac은 Intel/Apple Silicon 분리 노출 (자동 감지 대신) — 운영 단순성 + 사용자 명시적 선택
  - 코드 서명 보류 (CSC_IDENTITY_AUTO_DISCOVERY: false) — 개발 단계, 운영 진입 시 Apple Developer ID 추가 예정
metrics:
  duration: 12min
  completed: 2026-04-06
---

# Phase 11 Plan 05: GitHub Actions 크로스 빌드 + 자동 릴리즈 + 프론트 다운로드 UI Summary

태그 한 번 push로 Windows `.exe` + macOS `.dmg` 가 자동 빌드되어 GitHub Release 에 업로드되고, 프론트 PrinterConfigTab 의 다운로드 버튼이 영구 latest URL 로 즉시 동작하는 배포 파이프라인 구축. print-agent 를 gitlink 에서 일반 디렉토리로 승격해 CI checkout 가능 상태로 정리.

## What Was Built

### 1. Pre-flight: print-agent gitlink 승격

`print-agent` 는 root repo에 mode 160000 (gitlink) 로 등록되어 있었으나 `.gitmodules` 도 외부 remote 도 없어 `actions/checkout@v4` 가 빈 디렉토리로 처리하는 상태였다. 해결:

- `print-agent/.git` 제거 (사용자가 사전에 `~/backups/print-agent-history-2026_04_06.git` 백업 완료)
- `git rm --cached print-agent` 로 gitlink 엔트리 제거
- `git add print-agent/` 로 16개 파일을 root repo blob 으로 직접 추가
- 결과: `git ls-files print-agent` 가 main.js, src/*, renderer/*, package.json 등 출력

이후 모든 print-agent 변경사항은 root repo 단일 커밋으로 추적 가능.

### 2. GitHub Actions 워크플로우 (`.github/workflows/build-print-agent.yml`)

- 트리거: `print-agent-v*` 태그 push
- `permissions: contents: write` (Release 생성용)
- **build-windows** (`windows-latest`): checkout → setup-node 20 (root lockfile 캐시) → `npm ci` → `electron-builder install-app-deps --projectDir print-agent` → `npm run build:win -w print-agent` → softprops/action-gh-release@v2 로 `VentaGO-Print-Agent-Setup.exe` 업로드
- **build-macos** (`macos-latest`): 동일 패턴, `CSC_IDENTITY_AUTO_DISCOVERY: false` (코드 서명 비활성), `VentaGO-Print-Agent-x64.dmg` + `VentaGO-Print-Agent-arm64.dmg` 업로드
- 두 잡 모두 `fail_on_unmatched_files: true` — 파일명 불일치 시 즉시 에러로 조용한 실패 방지

### 3. `print-agent/package.json` 수정

- `build.publish: null` — electron-builder 자체 publish 비활성화 (Actions에 위임)
- `build.win.artifactName: "VentaGO-Print-Agent-Setup.${ext}"` — 버전 없는 고정 이름
- `build.mac.artifactName: "VentaGO-Print-Agent-${arch}.${ext}"` — arch 분리, 버전 없음
- `build:win` / `build:mac` 스크립트에 `--publish never` 명시
- `rebuild` 스크립트를 `electron-builder install-app-deps` 로 통일
- `files` 에 `package.json`, `!src/**/*.test.js`, `!ticket-preview.html` 정리

### 4. 프론트엔드 다운로드 UI (`ventago-app`)

**`src/config/printAgent.ts`** — 신규 상수 파일
```typescript
const REPO_BASE = 'https://github.com/jhkim1010/aceiii.online.1.0'
export const PRINT_AGENT_DOWNLOADS = {
  windows:      `${REPO_BASE}/releases/latest/download/VentaGO-Print-Agent-Setup.exe`,
  macosIntel:   `${REPO_BASE}/releases/latest/download/VentaGO-Print-Agent-x64.dmg`,
  macosArm:     `${REPO_BASE}/releases/latest/download/VentaGO-Print-Agent-arm64.dmg`,
  releasesPage: `${REPO_BASE}/releases`,
}
```

**`PrinterConfigTab.tsx`** — Wave 4 의 비활성(`disabled`) 다운로드 버튼 2개를 실제 동작하는 버튼 3개로 교체:
- Windows (.exe) — `variant="contained"`
- Mac Intel (.dmg) — `variant="outlined"`
- Mac Apple Silicon (.dmg) — `variant="outlined"`
- "Ver versiones ↗" — Releases 페이지 새 탭

모든 버튼은 `href` + `download` 속성으로 영구 latest URL 직접 링크. JS 호출/상태 관리 불필요.

### 5. 운영 가이드 (`print-agent/RELEASE.md`)

- 빠른 절차 (version bump → tag → push)
- 영구 다운로드 URL 표
- 최초 설정 체크리스트 8개 항목 (origin 확인 → Workflow permissions → 첫 태그 → Actions/Releases 검증 → 프론트 E2E)
- 롤백 방법 (Releases 수동 삭제로 직전 태그가 자동 latest 승격)
- 트러블슈팅: escpos-usb 컴파일 / macOS Gatekeeper / fail_on_unmatched_files

## Plan vs Implementation

### 차이점

1. **PrinterConfigTab 위치 차이** — 플랜은 `ventago-app/src/views/sucursales/PrinterConfigTab.tsx` 를 가정했으나 Wave 4 에서 실제로 생성된 위치는 `ventago-app/src/views/branches/components/printer/PrinterConfigTab.tsx`. 기존 파일을 그대로 편집 (이동 없음).
2. **PrinterConfigTab 구조 유지** — 플랜은 SWR + Dialog 기반의 새 구현체를 제시했지만, Wave 4 에서 이미 useEffect 폴링 + window.confirm 기반으로 동작 중. 다운로드 섹션만 교체하는 최소 변경 적용 (Rule 3 — 환경 적합성, 불필요한 재작성 회피).
3. **macOS 코드 서명** — 플랜대로 `CSC_IDENTITY_AUTO_DISCOVERY: false` 적용. 운영 단계 진입 시 secrets 추가 필요 (RELEASE.md 트러블슈팅에 명시).
4. **워크플로우 `--workspaces=false` 플래그 제거** — 플랜의 fallback 패턴(`npm ci`)을 채택. 워크스페이스 전체 설치가 더 안정적이고 cache 활용 가능.

### 구조적 결정: ventago-app 서브모듈 커밋

`ventago-app` 는 외부 remote 가 있는 서브모듈이라 print-agent 와 달리 승격 대상이 아니다. 다운로드 UI 변경은 두 단계 커밋으로 처리:
1. 서브모듈 내부 커밋 (`ventago-app@64344eb`) — printAgent.ts + PrinterConfigTab.tsx 수정
2. root repo gitlink 포인터 bump (`a127c60`)

`api-ventago` 는 이번 plan 에서 변경 없음.

## Deviations from Plan

**[Rule 3 — Environment fit]** PrinterConfigTab 을 새 SWR 기반 구현체로 교체하지 않고, Wave 4 의 useEffect 폴링 구현체에 다운로드 섹션만 패치. 동일 기능을 더 적은 변경으로 달성.

**[Rule 3 — Environment fit]** 플랜이 가정한 PrinterConfigTab 경로(`views/sucursales/`)와 실제 경로(`views/branches/components/printer/`) 차이를 자동 흡수.

**경로 외 deviations 없음** — 워크플로우/패키징/문서화는 플랜 그대로 실행.

## Known Stubs

**없음.** 모든 다운로드 버튼은 실제 GitHub Releases URL 로 wiring 되었다. 첫 태그 push 전까지는 URL 이 404 를 반환하나, 이는 Step 6 체크리스트(최초 설정)에서 사용자가 수동 트리거하는 정상 흐름이며 stub 이 아니다.

## Phase 의존성 노트

- Wave 4 의 `emitFiscalReceipt` 호출처는 여전히 Phase 10 미구현 (TODO 코멘트). Wave 5 범위 외.
- Wave 3 print-agent 의 `/realtime` namespace ↔ Wave 4 PrintGateway 의 `/print-agent` namespace 불일치는 운영 진입 전 정리 필요. Wave 5 범위 외 (도구는 모두 갖춰짐).

## 완료 기준 검증

### Pre-flight (Step 0)
- [x] print-agent 가 root repo 일반 디렉토리로 승격됨 (gitlink 제거 — `c17e25f`)
- [x] `git ls-files print-agent` 가 16개 실제 파일 출력
- [x] Wave 1~4 작업물 무결성 — main.js, src/*, renderer/*, config.json 모두 보존
- [x] 사용자 사전 백업 완료 (`~/backups/print-agent-history-2026_04_06.git`)

### 빌드 파이프라인 (Step 1~2)
- [x] `.github/workflows/build-print-agent.yml` 커밋 (`9d74d34`)
- [x] root `npm ci` + `npm run build:win -w print-agent` 패턴
- [x] `electron-builder install-app-deps` 명시 단계로 escpos-usb 재빌드
- [x] win/mac 각각 `artifactName` 명시
- [x] `publish: null` 추가
- [x] `fail_on_unmatched_files: true` 적용
- [ ] `git tag print-agent-v*` push → GitHub Release 생성 — **사용자 수동 트리거 (Step 6)**
- [ ] 실제 .exe / .dmg 빌드 성공 검증 — 첫 태그 push 후 GitHub Actions 결과로 확인

### 다운로드 & UI (Step 3~4)
- [x] `releases/latest/download/` 영구 URL 패턴 채택 (artifactName 버전 없음)
- [x] `ventago-app/src/config/printAgent.ts` 추가 (repo slug 정확)
- [x] PrinterConfigTab — 3개 다운로드 버튼 (Windows / Mac Intel / Mac Apple Silicon)
- [x] PrinterConfigTab — Releases 페이지 링크 추가
- [x] Wave 4 에서 이미 동작 중인 API Key 표시/복사/재발급/서버 URL 코드블록 유지

### 문서화 (Step 5~6)
- [x] `print-agent/RELEASE.md` 작성 (절차 + URL 표 + 체크리스트 + 롤백 + 트러블슈팅)
- [ ] Step 6 체크리스트 8 항목 — 처음 6개는 본 plan 에서 충족, 항목 7~8 은 사용자 첫 태그 push 후 검증 (사용자 가이드대로 진행)

### 명시적으로 보류된 항목
- 실제 `git push --tags` 미수행 — 사용자가 RELEASE.md 절차에 따라 수동 트리거 (요청대로 보류)

## Commits

| Repo        | Hash    | Message                                                                              |
| ----------- | ------- | ------------------------------------------------------------------------------------ |
| root        | c17e25f | chore(11-05): promote print-agent gitlink to regular directory for CI                |
| root        | 37675d7 | chore(11-05): add artifactName + publish:null for stable release file names          |
| root        | 9d74d34 | ci(11-05): add cross-platform build workflow for print-agent                         |
| ventago-app | 64344eb | feat(11-05): wire print-agent download buttons to GitHub Releases                    |
| root        | a127c60 | chore(11-05): bump ventago-app pointer for print-agent download UI                   |
| root        | 08b6279 | docs(11-05): add print-agent release procedure guide                                 |

## Self-Check: PASSED

All 4 created files exist on disk. All 5 commits found in git log.
