# PEDIDO 32 — Print Agent «Actualizar» 를 누르면 앱만 닫히고 업데이트가 안 된다

- 매장: cool (store 6) · 작성: israel samuel · 2026-10-14 09:11
- 원문: «al presionar actualizar y actualizar, solo cierra la app, no actualiza.» (사진: v1.2.18)
- 분류: **버그** (업데이트 설치 실패)

## 현재 상태 — 실측

운영 `branch_agents.agent_version` (최근 14일 접속):

| 종류 | 버전 분포 | 최신 릴리스 |
|---|---|---|
| thermal (print-agent) | 1.2.1 · 1.2.5 · 1.2.6 · 1.2.12 · 1.2.18 ×2 · 1.2.19 | **1.2.19** |
| zebra (zebra-agent) | 1.0.38 · 1.0.39 · 1.0.42 | 1.0.42 |

print-agent 는 2026-10-06 「물어보고 설치」 업데이트(1.2.11~) 이후에도 1.2.5·1.2.6·1.2.12 에
머문 PC 가 있다. 업데이트가 **매장 전반에서 안 먹고 있을** 가능성이 크다.

## 원인 (유력)

`print-agent/installer.nsh:14` — 설치 프로그램이 시작하자마자(.onInit) 실행하는 줄:

```nsis
nsExec::Exec 'taskkill /F /T /IM "${PRODUCT_FILENAME}.exe"'
```

- 「Actualizar ahora」 → `autoUpdater.quitAndInstall()` 은 **앱 프로세스가 설치 프로그램을 자식으로
  띄우고**(`BaseUpdater.js` `spawn(..., { detached: true })`) 종료한다.
- `/T` 는 **프로세스 트리 전체**(자식 포함)를 강제 종료한다. Windows 의 `detached` 는 부모-자식
  관계를 끊지 않는다 → 설치 프로그램이 **자기 자신을 죽인다.** 남는 것은 「앱이 닫혔다」 뿐.
- 대조: electron-builder 기본 종료 로직(`allowOnlyOneInstallerInstance.nsh`)은
  `taskkill /im … /fi "PID ne $pid"` — **`/T` 없이, 자기 PID 를 빼고** 죽이며, 업데이트일 때는
  (`${isUpdated}`) 앱이 스스로 닫히기를 먼저 기다린다. 우리 줄이 그 보호를 앞질러 무력화한다.
- 대조군: **zebra-agent 는 updater.js 가 완전히 같은데 `installer.nsh` 가 없다**
  → 매장 zebra 는 오늘 릴리스(1.0.39·1.0.42)까지 올라와 있다.

★ Windows 실기 재현은 아직 안 했다(이 Mac 에서 불가). 위는 코드·대조군 근거다.

## 제안 (권고안)

1. `installer.nsh` 의 `taskkill` 을 **업데이트가 아닐 때만**, **`/T` 없이**, **자기 PID 제외**로:
   ```nsis
   ${ifNot} ${isUpdated}
     nsExec::Exec `cmd /c taskkill /F /IM "${PRODUCT_FILENAME}.exe" /FI "USERNAME eq %USERNAME%"`
   ${endIf}
   ```
   (업데이트 경로는 electron-builder 기본 로직이 앱 종료를 기다린 뒤 닫는다.)
2. 잔재 삭제(`RMDir /r …`)는 그대로 둔다.
3. 옛 버전 PC 도 자동으로 올라올 수 있다: 업데이트 때 도는 것은 **새로 내려받은 설치 프로그램**
   (= 고친 1.2.20 의 installer.nsh)이기 때문이다. ⤷ 확인 필요: 배포 후 cool 매장에서 「Actualizar」
   한 번으로 올라오는지. 안 되면 설치 파일 직접 실행 안내(아래 답변 초안 B).
4. 릴리스: print-agent 태그 수동 증가(push-both.sh 는 커밋 후 스킵 — 메모리 참조) → GitHub Actions 빌드.

## 범위 밖
- zebra-agent: installer.nsh 없음 → 변경 없음.
- 「물어보고 설치」 정책(2026-10-06)은 유지.

## 영향 · 위험
- 앱 api / DB 변경 없음. print-agent 설치 스크립트만.
- 위험: 수동 설치(설치 파일 더블클릭) 때 실행 중인 에이전트를 닫는 동작은 유지(업데이트가 아닐 때만).
- 규모: **S**. 검증: Actions 빌드 성공 + Windows PC 1대에서 1.2.19→1.2.20 「Actualizar」 실측.

## 매장 답변 초안 (스페인어)

A (수정 배포 후):
> Encontramos la causa: el instalador cerraba también el proceso de la actualización. Ya está
> corregido en la versión 1.2.20. Abrí el Print Agent y presioná «Buscar actualización» →
> «Actualizar ahora». Si no se actualiza, avisanos y te pasamos el instalador.

B (자동으로 안 될 경우):
> Descargá el instalador desde Herramientas → Print Agent y ejecutalo. Tu configuración y la
> API Key se conservan.
