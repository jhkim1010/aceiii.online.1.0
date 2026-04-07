# VentaGO Print Agent — Release Procedure

새 버전 빌드 + 배포는 GitHub Actions가 자동 처리한다.
개발자는 root repo에서 태그 push 한 번이면 끝.

---

## 빠른 절차

```bash
cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0

# 1. print-agent/package.json 의 version 수동 편집
#    "version": "1.0.0" → "1.0.1"
$EDITOR print-agent/package.json

# 2. 커밋 + 태그 + push
git add print-agent/package.json
git commit -m "chore: bump print-agent to v1.0.1"
git tag print-agent-v1.0.1
git push origin main --tags
```

GitHub Actions 가 자동 실행:

- `windows-latest` → `VentaGO-Print-Agent-Setup.exe`
- `macos-latest`   → `VentaGO-Print-Agent-x64.dmg` + `VentaGO-Print-Agent-arm64.dmg`

5~12분 후 GitHub Release `print-agent-v1.0.1` 에 3개 파일이 업로드된다.

---

## 영구 다운로드 URL

태그 값과 무관하게 항상 최신 버전을 가리킨다.

| 플랫폼            | URL                                                                                                                |
| ----------------- | ------------------------------------------------------------------------------------------------------------------ |
| Windows           | https://github.com/jhkim1010/aceiii.online.1.0/releases/latest/download/VentaGO-Print-Agent-Setup.exe              |
| macOS Intel       | https://github.com/jhkim1010/aceiii.online.1.0/releases/latest/download/VentaGO-Print-Agent-x64.dmg                |
| macOS Apple Silicon | https://github.com/jhkim1010/aceiii.online.1.0/releases/latest/download/VentaGO-Print-Agent-arm64.dmg            |

프론트엔드 `ventago-app/src/config/printAgent.ts` 가 이 URL을 참조한다.
파일명 변경 시 양쪽을 동시에 업데이트해야 한다.

---

## 최초 설정 체크리스트

1. GitHub 저장소 origin 확인
   ```bash
   git remote -v
   # https://github.com/jhkim1010/aceiii.online.1.0.git
   ```

2. `.github/workflows/build-print-agent.yml` 가 main 에 존재해야 함

3. GitHub 저장소 **Settings → Actions → General → Workflow permissions**
   → "Read and write permissions" 활성화 (Release 생성 권한)

4. 첫 태그 push
   ```bash
   git tag print-agent-v1.0.0
   git push origin main --tags
   ```

5. **Actions 탭** 에서 두 잡 (Windows / macOS) 모두 green 확인

6. **Releases 탭** 에서 3개 파일 업로드 확인

7. 영구 latest URL 동작 확인 (브라우저로 직접 접속)

8. 프론트 PrinterConfigTab 에서 다운로드 버튼 클릭 → 실제 파일 다운로드 검증

---

## 롤백

문제 있는 릴리즈는 GitHub Releases 페이지에서 수동 삭제.
삭제 후 직전 태그가 자동으로 `latest` 로 승격된다.

---

## 트러블슈팅

### 빌드가 `escpos-usb` 컴파일 에러로 실패

→ `electron-builder install-app-deps` 단계 확인. 워크플로우 안에서
`npx --yes electron-builder install-app-deps --projectDir print-agent`
스텝이 명시적으로 실행되어야 한다.

### macOS DMG 가 "손상되었습니다" 경고

→ 코드 서명 미적용 (`CSC_IDENTITY_AUTO_DISCOVERY: false`).
사용자는 **System Settings → Privacy & Security** 에서 "Open Anyway" 클릭.
운영 단계 진입 시 Apple Developer ID 인증서 + `CSC_LINK` / `CSC_KEY_PASSWORD`
secrets 등록으로 해소.

### `fail_on_unmatched_files` 로 워크플로우가 즉시 실패

→ `print-agent/package.json` 의 `build.win.artifactName` /
`build.mac.artifactName` 와 워크플로우의 `files:` glob 이 정확히
일치해야 한다. 파일명 변경 시 양쪽 동시 수정 필수.
