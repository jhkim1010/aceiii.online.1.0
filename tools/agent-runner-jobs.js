/**
 * Agent Runner 허용 작업 정의 — 러너가 작업 실행 시마다 fresh 하게 로드하므로
 * 여기에 항목을 추가해도 러너 재시작이 필요 없다.
 *
 * 형식: cmd 이름 → { file, args(고정 배열 또는 (arg)=>배열), env? }
 * env: true 이면 tools/manuales/.env 를 로드해 자식 프로세스에 전달.
 */

module.exports = {
  // 매뉴얼 화면 캡처 (자격증명은 .env 에서)
  'capture-ventas': { file: 'node', args: ['tools/manuales/capture-ventas.js'], env: true },

  // 전 영역(Producto/Admin/Stock/MP/Talleres) 캡처
  'capture-manuales': { file: 'node', args: ['tools/manuales/capture-manuales.js'], env: true },

  // docx 빌드 — arg 로 content-*.js 지정
  'build-manual': {
    file: 'node',
    args: (arg) => {
      if (!/^content-[a-z-]+\.js$/.test(arg || '')) throw new Error('arg 는 content-*.js 형식이어야 함');

      return ['tools/manuales/build-manual.js', arg, 'docs/manuales'];
    },
  },

  // Trello 동기화 (Hechos 이동 + 카드 업데이트 + 첨부 포함)
  'trello-sync': { file: 'node', args: ['tools/trello-sync.js'] },

  // main push — ventago-app / api-ventago / 루트 순서로 push (Mac 자격증명 사용)
  'push-main': { file: 'bash', args: ['tools/push-main.sh'] },

  // 러너 생존 확인용 ping (Claude 원격 진단)
  'ping': { file: 'echo', args: ['pong'] },

  // ventago-admin-app macOS 디버그 빌드 (컴파일 검증 — flutter run 대체)
  'flutter-admin-build': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-admin-app && flutter build macos --debug 2>&1 | tail -30'],
  },

  // admin 앱 정적 분석 (빌드 충돌 없음 — flutter run 과 병행 안전)
  'flutter-admin-analyze': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-admin-app && dart analyze lib 2>&1 | tail -20'],
  },

  // flutter 경로 진단
  'which-flutter': {
    file: 'zsh',
    args: ['-ilc', 'which flutter dart; echo PATH=$PATH'],
  },

  // 빌드된 admin 앱 실행 (print 로그는 .planning/admin-app.log 로)
  'flutter-admin-open': {
    file: 'bash',
    args: ['-lc', 'APP=ventago-admin-app/build/macos/Build/Products/Debug/ventago_admin_app.app/Contents/MacOS/ventago_admin_app; pkill -f "MacOS/ventago_admin_app" 2>/dev/null; sleep 1; nohup "$APP" > .planning/admin-app.log 2>&1 & echo "launched pid=$!"'],
  },

  // admin 앱 stdout 로그 조회 (마지막 로그 확인용)
  'admin-app-log': {
    file: 'bash',
    args: ['-lc', 'tail -60 .planning/admin-app.log 2>/dev/null || echo "(로그 없음)"'],
  },

  // api 배포 전 검증 — 타입체크 + 변경영역 테스트
  'api-verify': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json && npx jest src/app/afip src/app/admin-console src/app/suspended-sales src/app/mobile --silent --forceExit --maxWorkers=2 2>&1 | tail -15'],
  },

  // 프론트 lint (Descargas 카드 파일)
  'eslint-front': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-app && npx eslint src/pages/herramientas/print-agent/index.tsx --fix && echo LINT_OK'],
  },

  // main 통합 + push + 브랜치 정리 (승인 후에만 enqueue)
  'integrate-main': { file: 'bash', args: ['tools/integrate-main.sh'] },

  // 실패 테스트 상세
  'api-verify-detail': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx jest src/app/afip src/app/admin-console src/app/suspended-sales src/app/mobile --forceExit --maxWorkers=2 2>&1 | grep -E "FAIL|✕|●" | head -25'],
  },

  'suspended-test-detail': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx jest src/app/suspended-sales --forceExit 2>&1 | grep -B2 -A12 "●.*ID로 삭제" | head -40'],
  },

  // main 직접 커밋+push (소규모 핫픽스)
  'commit-push-main': { file: 'bash', args: ['tools/commit-push-main.sh'] },

  // 에이전트 릴리즈 태그 push — GitHub Actions 빌드 트리거. arg = 태그명
  // (태그 자체는 Claude 가 로컬 생성 — 샌드박스에는 GitHub 자격증명이 없어 push 만 위임)
  'push-agent-tag': {
    file: 'git',
    args: (arg) => {
      if (!/^(print|zebra)-agent-v\d+\.\d+\.\d+$/.test(arg || '')) throw new Error('arg 는 (print|zebra)-agent-vX.Y.Z 태그명이어야 함');

      return ['push', 'origin', arg];
    },
  },

  // 2026-07-11 main 통합 (print-agent 흐림픽스 + ventago-app push + 브랜치 정리)
  'integrate-main-20260711': { file: 'bash', args: ['tools/integrate-main-20260711.sh'] },

  // 판매원 앱 macOS 디버그 빌드 (2026-07-14 추가)
  'flutter-sales-build': {
    file: 'zsh',
    args: ['-ilc', 'cd mobile-sales-app && flutter build macos --debug 2>&1 | tail -30'],
  },

  // 빌드된 판매원 앱 실행 (로그 → .planning/sales-app.log)
  'flutter-sales-open': {
    file: 'bash',
    args: ['-lc', 'APP=mobile-sales-app/build/macos/Build/Products/Debug/mobile_sales_app.app/Contents/MacOS/mobile_sales_app; pkill -f "MacOS/mobile_sales_app" 2>/dev/null; sleep 1; nohup "$APP" > .planning/sales-app.log 2>&1 & echo "launched pid=$!"'],
  },

  // 판매원 앱 stdout 로그 조회
  'sales-app-log': {
    file: 'bash',
    args: ['-lc', 'tail -60 .planning/sales-app.log 2>/dev/null || echo "(로그 없음)"'],
  },

  // 판매원 앱 Android 릴리스 APK 빌드
  'flutter-sales-apk': {
    file: 'zsh',
    args: ['-ilc', 'cd mobile-sales-app && flutter build apk --release 2>&1 | tail -15'],
  },

  // flutter_secure_storage 10.x MacOsOptions API 확인 (일회성 진단)
  'cat-macos-options': {
    file: 'bash',
    args: ['-lc', 'cat ~/.pub-cache/hosted/pub.dev/flutter_secure_storage-10.3.1/lib/options/macos_options.dart ~/.pub-cache/hosted/pub.dev/flutter_secure_storage-10.3.1/lib/options/apple_options.dart 2>/dev/null | head -80'],
  },

  // 판매원 앱 ABI 분할 APK (arm64 단독 — 파일 크기 절감)
  'flutter-sales-apk-split': {
    file: 'zsh',
    args: ['-ilc', 'cd mobile-sales-app && flutter build apk --release --split-per-abi 2>&1 | tail -8'],
  },

  // mobile 모듈 단독 테스트 (암호 전환 검증)
  'mobile-test-only': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx jest src/app/mobile --forceExit --maxWorkers=2 2>&1 | tail -30'],
  },

  // 2026-07-14 모바일 암호전환 + ingreso-stock 커밋·push (1회성)
  'commit-api-20260714': { file: 'bash', args: ['tools/commit-api-20260714.sh'] },

  // 2026-07-14 전체 main 통합 (ventago-app lint 게이트 + root gitlink)
  'integrate-main-20260714': { file: 'bash', args: ['tools/integrate-main-20260714.sh'] },
};
