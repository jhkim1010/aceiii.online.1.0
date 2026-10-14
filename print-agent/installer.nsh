; ============================================================
; VentaGO Print Agent — 커스텀 NSIS 설치 스크립트
; 목적: 설치 시 이전 버전 "프로그램 파일"을 무조건 모두 제거한다.
;       (사용자 설정 / API Key 등 electron-store 데이터는 보존)
;
; electron-builder 가 설치 초기(.onInit)에 customInit 매크로를 호출하며,
; 본 매크로는 기본 제공되는 "이전 버전 자동 제거" 위에 추가로
; 잔재 파일까지 강제 삭제하는 안전장치 역할을 한다.
; ============================================================

!macro customInit
  ; --- 1) 실행 중인 에이전트 종료 (파일 잠금으로 인한 삭제 실패 방지) ---
  ; ★ [2026-10-14 PEDIDO 32] 「Actualizar」 를 누르면 앱만 닫히고 업데이트가 안 됐다.
  ;   종전 줄 `taskkill /F /T /IM ...` 의 /T 는 프로세스 **트리**를 죽인다. 자동 업데이트에서
  ;   이 설치 프로그램은 앱이 띄운 **자식**(electron-updater spawn detached — Windows 에선
  ;   부모-자식 관계가 남는다)이라 자기 자신까지 죽였다.
  ;   · 업데이트(--updated)일 때는 죽이지 않는다 — electron-builder 기본 로직
  ;     (allowOnlyOneInstallerInstance.nsh)이 앱이 스스로 닫히길 기다린 뒤 「PID ne 자기」로 닫는다.
  ;   · 설치 파일을 직접 실행할 때만 닫는다 — /T 없이(앱 실행 파일만. 설치 파일은 이름이
  ;     `VentaGO-Print-Agent-Setup.exe` 라 /IM 에 안 걸린다).
  ;   대조군: zebra-agent 는 updater.js 가 같고 이 파일이 없다 → 업데이트가 됐다.
  ${ifNot} ${isUpdated}
    nsExec::Exec 'taskkill /F /IM "${PRODUCT_FILENAME}.exe"'
    Pop $0
  ${endIf}

  ; --- 2) per-user 설치 경로(잔재 포함) 무조건 삭제 ---
  ;     oneClick + perMachine:false 기본 설치 위치
  RMDir /r "$LOCALAPPDATA\Programs\${PRODUCT_FILENAME}"

  ; --- 3) 과거 perMachine 설치분이 남아있을 경우 대비 (있을 때만 삭제됨) ---
  RMDir /r "$PROGRAMFILES\${PRODUCT_FILENAME}"
  RMDir /r "$PROGRAMFILES64\${PRODUCT_FILENAME}"

  ; --- 4) 현재 설치 대상 디렉토리 잔재 제거 (설치는 이후 단계에서 새로 생성) ---
  RMDir /r "$INSTDIR"

  ; 주의: $APPDATA\${PRODUCT_FILENAME} (electron-store 설정·API Key) 는
  ;       의도적으로 삭제하지 않는다 → 업데이트 시 API Key 재입력 불필요.
!macroend
