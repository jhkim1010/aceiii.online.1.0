// macOS 앱 번들 전체를 ad-hoc 서명한다 (2026-09-29).
//
// ★ 왜: 서명 인증서가 없어 electron-builder 가 서명을 건너뛰면(CSC_IDENTITY_AUTO_DISCOVERY=false),
//   실행 파일에는 링커의 임시 서명만 남고 번들(Info.plist·리소스)은 묶이지 않는다.
//   Apple Silicon 은 그런 앱을 인터넷에서 받으면 «손상되었기 때문에 열 수 없습니다» 로 막는다 —
//   우회 버튼도 없다. 번들 전체를 ad-hoc(`-`) 으로 서명하면 서명이 **유효**해져, 그 대신
//   «확인되지 않은 개발자» 경고가 뜨고 시스템 설정 › 개인정보 보호 및 보안 › «그래도 열기» 로 열 수 있다.
// ★ 근본 해결(경고 없이 열림)은 Apple Developer ID 서명 + 공증이다 — 계정이 필요하다.
// ★ afterPack 은 DMG 를 만들기 **전**에 돈다. 그래서 DMG 안의 앱이 서명된 상태가 된다.
const { execFileSync } = require('child_process')
const path = require('path')

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'darwin') return

  const app = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`)

  execFileSync('codesign', ['--force', '--deep', '--sign', '-', app], { stdio: 'inherit' })

  // 서명이 실제로 유효한지 여기서 확인한다 — 실패하면 빌드가 멈춘다(깨진 앱을 배포하지 않게).
  execFileSync('codesign', ['--verify', '--deep', '--strict', '--verbose=2', app], { stdio: 'inherit' })
}
