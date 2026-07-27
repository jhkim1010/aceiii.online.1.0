/**
 * Agent Runner 허용 작업 정의 — 러너가 작업 실행 시마다 fresh 하게 로드하므로
 * 여기에 항목을 추가해도 러너 재시작이 필요 없다.
 *
 * 형식: cmd 이름 → { file, args(고정 배열 또는 (arg)=>배열), env? }
 * env: true 이면 tools/manuales/.env 를 로드해 자식 프로세스에 전달.
 */

module.exports = {
  'gh-tienda-watch': { file: 'zsh', args: ['-ilc', "RID=$(gh run list --workflow build-tienda-admin-app.yml -L 1 --json databaseId -q \".[0].databaseId\"); echo \"watching $RID\"; gh run watch \"$RID\" --exit-status 2>&1 | tail -6; echo \"---release---\"; gh release view tienda-admin-app-v1.0.0 --repo jhkim1010/ventago-downloads 2>&1 | head -20; echo WATCH_DONE"] },
  'gh-tienda-ci': { file: 'zsh', args: ['-ilc', "gh run list --workflow build-tienda-admin-app.yml -L 3 2>&1 | head -20; echo \"---releases---\"; gh release view tienda-admin-app-v1.0.0 --repo jhkim1010/ventago-downloads 2>&1 | head -15; echo GH_CI_DONE"] },
  'tienda-git-push': { file: 'zsh', args: ['-ilc', "rm -f .git/index.lock 2>/dev/null || true; git add tienda-admin-app .github/workflows/build-tienda-admin-app.yml && git commit -m \"feat(tienda-admin-app): 매장 관리자 Flutter 앱 + CI 워크플로\" -m \"Panel·Caja(마감)·Reportes 16종·Usuarios/Permisos·사용자 CRUD\" -m \"Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\" && git push origin main && echo ROOT_PUSHED && git tag tienda-admin-app-v1.0.0 && git push origin tienda-admin-app-v1.0.0 && echo TAG_PUSHED && git log --oneline -1"] },
  'tienda-front-push': { file: 'zsh', args: ['-ilc', "cd ventago-app && rm -f .git/index.lock 2>/dev/null || true; git add src/pages/herramientas/print-agent/index.tsx && git commit -m \"feat(descargas): App Tienda Admin 다운로드 카드 추가\" -m \"Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\" && git push origin main && echo FRONT_PUSHED && git log --oneline -1"] },

  'tienda-apk-dropbox': { file: 'zsh', args: ['-ilc', 'SRC=tienda-admin-app/build/app/outputs/flutter-apk/app-release.apk; DST="/Users/marcoskim/Dropbox/ACE_3_uversion/app herramientas download/tienda-admin-android.apk"; if [ ! -f "$SRC" ]; then echo NO_APK; exit 1; fi; cp -f "$SRC" "$DST" && ls -la "$DST" && echo TIENDA_APK_DROPBOX_DONE'] },
  'tienda-apk': { file: 'zsh', args: ['-ilc', 'cd tienda-admin-app && flutter build apk --release --dart-define=BASE_URL=https://newapi.coolsistema.com/api > /tmp/tiendabuild.log 2>&1; RC=$?; tail -22 /tmp/tiendabuild.log; if [ $RC -ne 0 ]; then echo BUILD_FAIL rc=$RC; exit $RC; fi; ls -la build/app/outputs/flutter-apk/app-release.apk && echo TIENDA_APK_DONE'] },
  'tienda-analyze': { file: 'zsh', args: ['-ilc', 'cd tienda-admin-app && flutter pub get 2>&1 | tail -8 && echo "--ANALYZE--" && dart analyze lib 2>&1 | tail -80; echo TIENDA_ANALYZE_DONE'] },
  'discount-deploy-push': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add src/app/admin-console/admin-console.service.ts src/app/admin-console/admin-console.controller.ts migrations/2026-07-23-store-billing-discounts.sql && git commit -m "feat(admin-console): 매장 관리비 할인(recurrente/única vez) — A cobrar 순액 반영" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'admin-analyze-nav': { file: 'zsh', args: ['-ilc', 'cd ventago-admin-app && dart analyze lib/shared lib/features/console 2>&1 | tail -40; echo ANALYZE_DONE'] },
  'tenants-sort-deploy': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add src/app/admin-console/admin-console.service.ts && git commit -m "feat(admin-console): Clientes 목록을 그날 판매순(salesToday DESC)으로 정렬" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'sessionttl-deploy': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add src/app/session/guards/session.guard.ts src/app/session/session.module.ts src/app/session/session.cron.ts && git commit -m "feat(session): 6시간 이상 유휴 세션 자동 로그아웃(가드 거부 + 10분 정리 cron)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'dashcard-deploy': { file: 'zsh', args: ['-ilc', 'cd ventago-app && npx eslint src/views/dashboards/ventas/DashboardsSalesView.tsx --fix 2>&1 | tail -8; echo "--RECHECK--" && npx eslint src/views/dashboards/ventas/DashboardsSalesView.tsx 2>&1 | tail -15 && git add src/views/dashboards/ventas/DashboardsSalesView.tsx && git commit -m "feat(dashboard): Clientes 카드 클릭 시 고객 리스트(/clientes-globales)로 이동" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'softdel-deploy-push': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add src/app/store/store.model.ts src/app/admin-console/admin-console.service.ts src/app/admin-console/admin-console.controller.ts src/app/auth/auth.service.ts migrations/2026-07-23-store-soft-delete.sql && git commit -m "feat(admin-console): 매장 soft-delete + 복구(Borrados) — 삭제 시 직원 로그인 차단(superadmin 예외)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'softdel-verify': { file: 'zsh', args: ['-ilc', 'cd api-ventago && echo "--API TSC--" && npx tsc --noEmit -p tsconfig.build.json && echo API_TSC_OK && cd ../ventago-admin-app && echo "--DART--" && dart analyze lib/features/console 2>&1 | tail -30; echo VERIFY_DONE'] },
  'admin-apk-slidable': { file: 'zsh', args: ['-ilc', 'cd ventago-admin-app && flutter build apk --release --dart-define=BASE_URL=https://newapi.coolsistema.com/api > /tmp/adminbuild.log 2>&1; RC=$?; tail -18 /tmp/adminbuild.log; if [ $RC -ne 0 ]; then echo BUILD_FAIL rc=$RC; exit $RC; fi; DEST="/Users/marcoskim/Dropbox/Personal de m. Marcos/superadmin-ventago-android.apk"; cp build/app/outputs/flutter-apk/app-release.apk "$DEST" && ls -la "$DEST" && echo BUILD_COPY_DONE'] },
  'admin-analyze-slidable': { file: 'zsh', args: ['-ilc', 'cd ventago-admin-app && flutter pub get 2>&1 | tail -6 && echo "--ANALYZE--" && dart analyze lib/features/console lib/features 2>&1 | tail -40; echo ANALYZE_DONE'] },
  'productstock-sep-deploy': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx eslint src/app/products/productStock.service.ts --fix 2>&1 | tail -8; echo "--TSC--" && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add src/app/products/productStock.service.ts && git commit -m "perf(productStock): 상품목록 variants·Price separate:true (POS/재고 그리드 인라인 JOIN 행폭발 제거)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'products-sep-deploy': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx eslint src/app/products/products.service.ts --fix 2>&1 | tail -10; echo "--TSC--" && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add src/app/products/products.service.ts && git commit -m "perf(products): findLastCreated/findOneWithVariants variants·Price separate:true (인라인 JOIN 행폭발 제거)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'push-decimals-main': { file: 'bash', args: ['-lc', 'git push origin main 2>&1 | tail -5; echo PUSH_DECIMALS_MAIN_DONE'] },
  'metering-deploy': { file: 'zsh', args: ['-ilc', 'bash tools/metering-deploy.sh'] },
  'metering-verify': { file: 'zsh', args: ['-ilc', 'cd api-ventago && (npx eslint src/app/admin-console/admin-console.service.ts --fix 2>&1 | tail -8 || true) && echo "--TSC--" && npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK'] },
  'slowq-clear-deploy': { file: 'zsh', args: ['-ilc', 'bash tools/slowq-clear-deploy.sh'] },
  'slowq-deploy-push': { file: 'zsh', args: ['-ilc', 'cd api-ventago && git add src/database/database.module.ts src/app/products/products.service.ts && git commit -m "perf(diagnostics+products): slow_query_log 부팅/introspection/DDL 잡음 제외 + findFiltered variants/Price separate:true(행폭발 제거)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main && echo PUSH_OK && git log --oneline -1'] },
  'slowq-verify': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx eslint src/database/database.module.ts src/app/products/products.service.ts --fix 2>&1 | tail -20 && echo "--- TSC ---" && npx tsc --noEmit -p tsconfig.build.json 2>&1 | tail -25; echo SLOWQ_VERIFY_DONE'] },
  'flutter-admin-apk': { file: 'zsh', args: ['-ilc', 'cd ventago-admin-app && flutter build apk --release --dart-define=BASE_URL=https://newapi.coolsistema.com/api 2>&1'] },
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

  // Phase 58 — feature/phase58-offline-sync 3-repo main 병합 + push
  // (마운트 git lock 이슈 회피 — Mac 네이티브 실행)
  'integrate-phase58': { file: 'bash', args: ['tools/integrate-phase58.sh'] },

  // 러너 생존 확인용 ping (Claude 원격 진단)
  'ping': { file: 'echo', args: ['pong'] },
  // Jenkins 원격 빌드 트리거 — arg=잡이름. JENKINS_USER/JENKINS_TOKEN 은 tools/manuales/.env 에서 로드(env:true).
  'trigger-jenkins': {
    file: 'bash',
    env: true,
    args: (arg) => ['-c',
      'set -e; JOB="' + String(arg || '').replace(/[^a-zA-Z0-9._-]/g, '') + '"; '
      + 'if [ -z "$JENKINS_USER" ] || [ -z "$JENKINS_TOKEN" ]; then echo NO_JENKINS_CREDS; exit 2; fi; '
      + 'B="https://deploy.coolsistema.com"; CJ=$(mktemp); '
      + 'CRUMB=$(curl -s -c "$CJ" -u "$JENKINS_USER:$JENKINS_TOKEN" "$B/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)"); '
      + 'do_post(){ curl -s -o /dev/null -w "%{http_code}" -b "$CJ" -u "$JENKINS_USER:$JENKINS_TOKEN" -H "$CRUMB" -X POST "$1"; }; '
      + 'C1=$(do_post "$B/job/$JOB/build"); '
      + 'if [ "$C1" = "400" ]; then C2=$(do_post "$B/job/$JOB/buildWithParameters"); else C2="-"; fi; '
      + 'rm -f "$CJ"; echo "trigger $JOB build=$C1 buildWithParameters=$C2"; '
      + 'for C in "$C1" "$C2"; do case "$C" in 201|200|302) echo TRIGGER_OK; exit 0 ;; esac; done; echo TRIGGER_FAIL; exit 1'
    ],
  },
  'theme-migrate-slug': { file: 'zsh', args: ['-ilc', 'psql -w -h localhost -p 5432 -U postgres -d ventago -f api-ventago/migrations/2026-07-22-stores-slug.sql 2>&1 | tail -20; echo SLUG_MIGRATE_DONE'] },
  'ventago-fix-push': { file: 'zsh', args: ['-ilc', 'cd ventago-app; rm -f .git/index.lock; git add src/components/StorefrontDesignCard.tsx src/components/ThemeEditButton.tsx src/services/store-theme.service.ts; if git diff --cached --quiet; then echo NO_CHANGES; else git commit -m \"fix(theme): eslint lines-around-comment (공개몰 카드/서비스)\" -m \"Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>\" && git push origin main && echo PUSHED; fi; git log --oneline -1; echo VFIX_PUSH_DONE'] },
  'ventago-lint-fix': { file: 'zsh', args: ['-ilc', 'cd ventago-app && npx eslint src/components/StorefrontDesignCard.tsx src/components/ThemeEditButton.tsx src/services/store-theme.service.ts --fix 2>&1 | tail -5; echo \"--- RECHECK ---\"; npx eslint src/components/StorefrontDesignCard.tsx src/components/ThemeEditButton.tsx src/services/store-theme.service.ts 2>&1 | tail -25; echo VENTAGO_LINT_DONE'] },
  'theme-commit-push-2': { file: 'bash', args: ['tools/theme-commit-push-2.sh'] },
  'theme-migrate-enabled': { file: 'zsh', args: ['-ilc', 'psql -w -h localhost -p 5432 -U postgres -d ventago -f api-ventago/migrations/2026-07-22-store-themes-enabled.sql 2>&1 | tail -30; echo THEME_MIGRATE_ENABLED_DONE'] },
  // [2026-07-22] 매장 테마 Phase1 3-repo 커밋+push
  'theme-commit-push': { file: 'bash', args: ['tools/theme-commit-push.sh'] },
  // [2026-07-22] DI 부팅 프로브 (HTTP 없이 모듈 초기화)
  'theme-di-boot': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx ts-node -r tsconfig-paths/register scripts/_theme-di-probe.ts 2>&1 | tail -45; echo THEME_DI_DONE'] },
  // [2026-07-22] 매장 테마 Phase1 검증: api eslint + tsc build + tienda lint
  'theme-verify': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx eslint src/app/shop-public --fix 2>&1 | tail -30 && echo "--- API TSC ---" && npx tsc --noEmit -p tsconfig.build.json 2>&1 | tail -30 && echo "--- TIENDA LINT ---" && cd ../tienda-app && npm run lint 2>&1 | tail -15 && echo \"--- TIENDA TSC ---\" && npx tsc --noEmit 2>&1 | tail -25; echo THEME_VERIFY_DONE'] },
  // [2026-07-22] 로컬 5432 마이그 적용 (-w: 비번 프롬프트 금지, .pgpass 사용)
  'theme-migrate-local': { file: 'zsh', args: ['-ilc', 'psql -w -h localhost -p 5432 -U postgres -d ventago -f api-ventago/migrations/2026-07-22-store-themes.sql 2>&1 | tail -40; echo THEME_MIGRATE_DONE'] },

  // Facturar output 배선(WhatsApp/thermal/pdf)+offline-F10 선별 커밋+push (2026-07-22)
  'push-facturar-output': { file: 'bash', args: ['tools/push-facturar-output.sh'] },

  // WIRING GAP #1 fiscal 출력 배선 push (2026-07-22)
  'push-fiscal-wiring': { file: 'bash', args: ['tools/push-fiscal-wiring.sh'] },

  // AFIP 10015 docType/docNro 수정 push (2026-07-22)
  'push-afip-docfix': { file: 'bash', args: ['tools/push-afip-docfix.sh'] },

  // A4 PDF 재설계 + 감열 제목 push (2026-07-22)
  'push-afip-pdf': { file: 'bash', args: ['tools/push-afip-pdf.sh'] },

  // 매장별 comprobante 로고 push (2026-07-22)
  'push-afip-logo': { file: 'bash', args: ['tools/push-afip-logo.sh'] },

  'push-afip-fantasia': { file: 'bash', args: ['tools/push-afip-fantasia.sh'] },

  'push-genlogo': { file: 'bash', args: ['tools/push-genlogo.sh'] },

  'push-wa-fallback': { file: 'bash', args: ['tools/push-wa-fallback.sh'] },

  'push-afip-pdflink': { file: 'bash', args: ['tools/push-afip-pdflink.sh'] },
  'email-cfg-api-tsc': { file: 'zsh', args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json 2>&1 | tail -40; echo API_TSC_DONE'] },
  'front-email-verify': { file: 'zsh', args: ['-ilc', 'cd ventago-app && npx tsc --noEmit 2>&1 | tail -40; echo FRONT_TSC_DONE'] },
  'fix-campanas-front-eslint': { file: 'bash', args: ['tools/fix-campanas-front-eslint.sh'] },
  'fix-campaigns-ref': { file: 'bash', args: ['tools/fix-campaigns-ref.sh'] },
  'push-campanas-front-fix': { file: 'bash', args: ['tools/push-campanas-front-fix.sh'] },
  'push-campanas-front': { file: 'bash', args: ['tools/push-campanas-front.sh'] },
  'push-campanas-backend': { file: 'bash', args: ['tools/push-campanas-backend.sh'] },
  'push-campanas-optin': { file: 'bash', args: ['tools/push-campanas-optin.sh'] },
  'push-optin-form': { file: 'bash', args: ['tools/push-optin-form.sh'] },
  'push-email-resend-smtp': { file: 'bash', args: ['tools/push-email-resend-smtp.sh'] },
  'push-cliente-campanas-btn': { file: 'bash', args: ['tools/push-cliente-campanas-btn.sh'] },
  'push-campanas-a': { file: 'bash', args: ['tools/push-campanas-a.sh'] },
  'jenkins-status': { file: 'bash', env: true, args: (arg) => ['tools/jenkins-status.sh', String(arg || '').replace(/[^a-zA-Z0-9._-]/g,'')] },
  'gh-actions-status': { file: 'bash', args: (arg) => { const a=String(arg||'').split('|'); return ['tools/gh-actions-status.sh', a[0]||'build-print-agent.yml', a[1]||'print-agent-v1.0.18']; } },
  'push-fiscal-fontsize': { file: 'bash', args: ['tools/push-fiscal-fontsize.sh'] },
  'push-fiscal-blur-fix': { file: 'bash', args: ['tools/push-fiscal-blur-fix.sh'] },
  'push-afip-auto-thermal': { file: 'bash', args: ['tools/push-afip-auto-thermal.sh'] },
  'push-afip-email-cfg': { file: 'bash', args: ['tools/push-afip-email-cfg.sh'] },
  'migrate-campanas-local': { file: 'zsh', args: ['-ilc', 'psql -w -h localhost -p 5432 -U postgres -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/2026-07-22-campanas.sql 2>&1 | tail -12; echo MIGRATE_CAMPANAS_LOCAL_DONE'] },
  'migrate-email-cfg-local': { file: 'zsh', args: ['-ilc', 'psql -w -h localhost -p 5432 -U postgres -d ventago -f api-ventago/migrations/2026-07-23-store-email-config.sql 2>&1 | tail -8; echo MIGRATE_LOCAL_DONE'] },
  'push-afip-email': { file: 'bash', args: ['tools/push-afip-email.sh'] },
  'push-afip-pctfix': { file: 'bash', args: ['tools/push-afip-pctfix.sh'] },
  'retrigger-ci-api': { file: 'bash', args: ['-lc', 'cd api-ventago && rm -f .git/index.lock 2>/dev/null || true; git commit --allow-empty -m "chore: re-trigger CI (webhook re-fire)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" && git push origin main 2>&1 | tail -4; echo RETRIGGER_DONE; git log --oneline -1'] },

  'revert-pim': { file: 'bash', args: ['tools/revert-pim.sh'] },

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

  // Phase 57 검증 — 클라우드 VM 마운트 FS 에서 eslint/tsc 가 사실상 불가라 Mac 네이티브로 실행
  'phase57-eslint-api': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx eslint src/app/dashboard-admin/ src/app.module.ts && echo LINT_OK'],
  },
  'integrate-api-inspect-conflict': {
    file: 'bash',
    args: ['-lc', 'cd api-ventago && git status --porcelain | grep -E "^(UU|AA|DD)" | head -5; echo "== main1 이 products.model 을 건드렸나:"; git diff $(git merge-base main1 HEAD)..main1 --stat | cat | head -10; echo "== 충돌 마커 주변:"; grep -n -A2 -B2 "<<<<<<<" src/app/products/products.model.ts | head -20'],
  },
  'vto-migrate-local': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && psql -h localhost -p 5432 -U postgres -d ventago -v ON_ERROR_STOP=0 -f migrations/2026-07-16-vto-metering.sql 2>&1 | tail -8; echo VTO_MIGRATE_DONE'],
  },
  'vto-push-front': {
    file: 'bash',
    args: ['-lc', 'cd ventago-app && git push origin main 2>&1 | tail -3; git fetch origin main 2>&1 | tail -1; git rev-list --left-right --count origin/main...main'],
  },
  'vto-push-all': {
    file: 'bash',
    args: ['-lc', 'set -e; for r in mobile-sales-app api-ventago ventago-app; do echo "== $r"; git -C $r push origin main 2>&1 | tail -2; done; rm -f .git/index.lock; git add api-ventago ventago-app mobile-sales-app tools/agent-runner-jobs.js && (git diff --cached --quiet || git commit -m "chore: VTO 미터링 3-repo 포인터 갱신 (Phase 49-M)" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>") && git push origin main 2>&1 | tail -2; echo PUSH_ALL_DONE'],
  },
  'vto-verify-front': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-app && npx eslint src/context/StoreConfigContext.tsx src/views/configuracion/vto/VtoConfigView.tsx src/views/admin/vto/VtoAdminView.tsx src/pages/admin/vto.tsx src/pages/configuracion/index.tsx src/navigation/menuRegistry.ts --fix 2>&1 | tail -25 && npx tsc --noEmit 2>&1 | tail -15; echo VTO_FRONT_DONE'],
  },
  'vto-verify-dart': {
    file: 'zsh',
    args: ['-ilc', 'cd mobile-sales-app && dart analyze lib/features/product lib/features/tryon lib/features/auth lib/core/network 2>&1 | tail -15; echo VTO_DART_DONE'],
  },
  'vto-verify': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx eslint src/app/vto src/app/tryon/mobile-tryon.controller.ts src/app/tryon/fashn-tryon.provider.ts src/app/tryon/tryon-provider.interface.ts src/app/tryon/tryon.module.ts src/app/store/config/storeConfig.model.ts src/app/store/config/storeConfig.controller.ts src/app/mobile/auth/mobile-auth.service.ts src/app/mobile/mobile.module.ts src/app.module.ts --fix 2>&1 | tail -25 && npx tsc --noEmit -p tsconfig.build.json 2>&1 | tail -10; echo VTO_VERIFY_DONE'],
  },
  'push-api-main': {
    file: 'bash',
    args: ['-lc', 'cd api-ventago && git push origin main 2>&1 | tail -3; git rev-list --left-right --count origin/main...main'],
  },
  'integrate-api-final-check': {
    file: 'bash',
    args: ['-lc', 'cd api-ventago && echo "PR본 refs=$(git show f6489b2:src/app/products/products.module.ts | grep -c SkuSerial) vs 병합본 refs=$(grep -c SkuSerial src/app/products/products.module.ts)"; echo "model serial 필드 중복 체크=$(grep -c \"str_prefix\" src/app/products/products.model.ts)"'],
  },
  'integrate-api-resolve': {
    file: 'bash',
    args: ['-lc', 'cd api-ventago && git checkout --ours src/app/products/products.model.ts migrations/2026-07-16-sku-serials.sql && git add src/app/products/products.model.ts migrations/2026-07-16-sku-serials.sql && git commit --no-edit 2>&1 | tail -2; git log --oneline -2 | cat; echo "module_files=$(ls src/app/dashboard-admin 2>/dev/null | wc -l)"; echo "conflicts_left=$(git status --porcelain | grep -cE \"^(UU|AA)\")"; echo "skuserial_refs=$(grep -c SkuSerial src/app/products/products.module.ts)"'],
  },
  'integrate-api-main1': {
    file: 'bash',
    args: ['-lc', 'cd api-ventago && rm -f .git/index.lock && git merge main1 --no-edit 2>&1 | tail -3; git log --oneline -3 | cat; echo "module_files=$(ls src/app/dashboard-admin 2>/dev/null | wc -l)"; echo "appmodule_refs=$(grep -c DashboardAdminModule src/app.module.ts)"'],
  },
  'integrate-verify-content': {
    file: 'bash',
    args: ['-lc', 'cd ventago-app && echo "front main:"; ls src/navigation/menuRegistry.ts src/views/dashboards/admin/ControlCenterView.tsx src/views/homes/components/ProductList/components/EnvioClientPanel.tsx 2>&1 | head -4; git log --oneline main -8 | cat; git rev-list --left-right --count origin/main...main 2>/dev/null; cd ../api-ventago && echo "api main:"; ls src/app/dashboard-admin 2>&1 | head -2; grep -c DashboardAdminModule src/app.module.ts; git rev-list --left-right --count origin/main...main 2>/dev/null'],
  },
  'integrate-inspect': {
    file: 'bash',
    args: ['-lc', 'for r in ventago-app api-ventago; do echo "== $r"; cd $r; rm -f .git/index.lock; git branch --show-current; git status --porcelain | grep -v _to_delete | head -6; git log --oneline -1; git branch --merged main | tr "\\n" " "; echo; cd ..; done'],
  },
  'vto-fee-caption': {
    file: 'zsh',
    args: ['-ilc', 'cd mobile-sales-app && dart analyze lib/features/product 2>&1 | tail -6 && rm -f .git/index.lock && git add lib/features/product/views/product_detail_screen.dart && git -c user.name="Marcos.J.Kim" -c user.email="junghokim10@gmail.com" commit -m "feat(tryon): Prueba Virtual 버튼에 사용료 안내(\$200/생성) 캡션" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" 2>&1 | tail -2; git log --oneline -1'],
  },
  'phase57-cherry-pick': {
    file: 'bash',
    args: ['-lc', 'cd api-ventago && rm -f .git/index.lock .git/HEAD.lock && git cherry-pick 8e575f6 2>&1 | tail -4; echo "HEAD: $(git log --oneline -1)"; ls src/app/dashboard-admin | wc -l'],
  },
  'check-dev-servers': {
    file: 'bash',
    args: ['-lc', 'echo "front:$(curl -s -o /dev/null -w %{http_code} --max-time 4 http://localhost:3050)"; echo "api:$(curl -s -o /dev/null -w %{http_code} --max-time 4 http://localhost:5002/api)"; pgrep -fl "next dev" | head -2; pgrep -fl "nest start" | head -2'],
  },
  'envio-capture-verify': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-app && npx eslint src/views/homes/components/ProductList/components/EnvioClientPanel.tsx src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx src/views/homes/components/ProductList/components/EnvioRegistroModal.tsx --fix && npx tsc --noEmit 2>&1 | tail -20; echo ENVIO_VERIFY_DONE'],
  },
  'phase57-migrate-local': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && for f in migrations/2026-07-14-branch-is-warehouse.sql migrations/store-notices.sql migrations/store-error-log.sql; do echo "== $f"; psql -h localhost -p 5432 -U postgres -d ventago -v ON_ERROR_STOP=0 -f "$f" 2>&1 | tail -5; done; echo MIGRATE_LOCAL_DONE'],
  },
  'phase57-eslint-api-fix': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx eslint src/app/dashboard-admin/ src/app.module.ts --fix && echo FIX_LINT_OK'],
  },
  'phase57-tsc-api': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx tsc --noEmit -p tsconfig.build.json 2>&1 | tail -15; echo TSC_DONE'],
  },
  'phase57-verify-front': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-app && npx eslint src/navigation/ src/pages/configuracion/index.tsx src/hooks/api/useAdminControlCenter.ts src/views/dashboards/admin/ControlCenterView.tsx src/pages/dashboards/admin/index.tsx src/views/configuracion/transporte/TransporteCard.tsx --fix && npx tsc --noEmit 2>&1 | tail -20; echo FRONT_DONE'],
  },

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

  // 2026-07-14 프론트 브랜치 → main ff 병합 + push
  'merge-front-main-20260714': { file: 'bash', args: ['tools/merge-front-main-20260714.sh'] },

  'cleanup-front-branch-20260714': { file: 'bash', args: ['tools/cleanup-front-branch-20260714.sh'] },

  'final-housekeep-20260714': { file: 'bash', args: ['tools/final-housekeep-20260714.sh'] },
  // 2026-07-20 Phase 59 SOAP 직접 발행 — 브랜치 생성+커밋 (push 없음)
  'phase59-branch-commit': { file: 'bash', args: ['tools/phase59-branch-commit.sh'] },
  // Phase 59 — afip 스위트 실패 식별 (FAIL/개별 실패 라인만)
  'phase59-afip-test': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx jest src/app/afip --forceExit --maxWorkers=2 2>&1 | grep -E "FAIL|✕|✗|Tests:|●" | head -40'],
  },
  // Phase 59 — voucher 스펙(스텁 throw 검증) 갱신 추가 커밋
  'phase59-commit-spec-fix': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && git checkout feature/phase59-afip-soap 2>&1 | tail -1 && git add src/app/afip/afip-voucher.service.spec.ts && (git diff --cached --quiet || git commit -m "test(phase59): voucher resolveProvider soap 실구현 반영") && git log --oneline -2'],
  },
  // Phase 59 Wave B — homologación E2E (WSAA 로그인 → CAE 발급 → 재조회)
  'phase59-homo-e2e': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && git checkout feature/phase59-afip-soap 2>&1 | tail -1 && npx ts-node -r tsconfig-paths/register scripts/phase59-homo-e2e.ts 2>&1 | tail -30'],
  },
  // Phase 59 — homo E2E 스크립트 커밋
  'phase59-commit-e2e': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && git checkout feature/phase59-afip-soap 2>&1 | tail -1 && git add scripts/phase59-homo-e2e.ts && (git diff --cached --quiet || git commit -m "test(phase59): homologación E2E 스크립트 — WSAA·FEDummy·CondIVA파라미터·C/B/NC 발급·FECompConsultar 전 경로 통과") && git log --oneline -3'],
  },
  // 2026-07-20 Phase 59 main 병합+push (api + root .gsd/tools)
  'integrate-phase59': { file: 'bash', args: ['tools/integrate-phase59.sh'] },
  // Phase 59 Wave C — 인증서 마운트 compose 커밋+push (main 직접)
  'phase59-commit-compose': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && git checkout main 2>&1 | tail -1 && git add docker-compose.yml && (git diff --cached --quiet || git commit -m "chore(phase59): AFIP 인증서 폴더 마운트 + AFIP_CERTS_DIR (게이트웨이 공유)") && git push origin main && git log --oneline -1'],
  },
  // Phase 59 FIX-A — 이중발급 가드 검증(eslint+jest afip)+커밋 (push 없음)
  'phase59-fixa-verify-commit': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && git checkout main 2>&1 | tail -1 && npx eslint src/app/afip/afip-voucher.service.ts src/app/afip/providers/soap-direct.provider.ts src/app/afip/afip-voucher.service.spec.ts src/app/afip/providers/soap-direct.provider.spec.ts --fix 2>&1 | tail -5; npx jest src/app/afip --forceExit --maxWorkers=2 2>&1 | grep -E "FAIL|✕|Tests:" | head -20 && git add src/app/afip/afip-voucher.service.ts src/app/afip/providers/soap-direct.provider.ts src/app/afip/afip-voucher.service.spec.ts src/app/afip/providers/soap-direct.provider.spec.ts && (git diff --cached --quiet || git commit -m "fix(phase59): 이중발급 가드 — 원자적 상태 클레임 + 발급률 상한 + ambiguous 조회 지연 (FIX-A)") && git log --oneline -1'],
  },
  // FIX-A 실패 테스트 상세
  'phase59-fixa-detail': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && npx jest src/app/afip/afip-voucher.service.spec.ts --forceExit --maxWorkers=1 2>&1 | grep -B2 -A18 "●.*›" | head -60'],
  },
  // Phase 59 — 발급 버튼 이중클릭 방지 lint+커밋 (push 없음)
  'phase59-front-doubleclick': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-app && git checkout main 2>&1 | tail -1 && npx eslint src/views/facturacion/PartialInvoiceModal.tsx --fix 2>&1 | tail -5; npx tsc --noEmit 2>&1 | grep PartialInvoice | head -5; git add src/views/facturacion/PartialInvoiceModal.tsx && (git diff --cached --quiet || git commit -m "fix(phase59): Emitir 버튼 이중클릭 방지 — 동기 ref 가드 + 성공 시 잠금 유지 + 전송 중 닫기 차단") && git log --oneline -1'],
  },
  // Phase 59 — FIX-A(api)+이중클릭 방지(front) main push
  'phase59-push-final': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && git checkout main 2>&1 | tail -1 && git push origin main && cd ../ventago-app && git checkout main 2>&1 | tail -1 && git push origin main && echo PUSH-OK && git -C ../api-ventago log --oneline -1 && git log --oneline -1'],
  },

  // [2026-07-24] Tienda Web 게시 토글 — api(커밋됨 9a0fd65) tsc 게이트+push, front lint 게이트+선별 커밋+push
  'tienda-publish-api-push': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && rm -f .git/*.lock .git/*.stale* 2>/dev/null; npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git push origin main && echo API_PUSH_OK && git log --oneline -1'],
  },
  // api local main 이 origin 보다 뒤 → autostash rebase(더러운 작업트리 보존) 후 push
  'tienda-publish-api-rebase-push': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && rm -f .git/*.lock 2>/dev/null; git -c rebase.autoStash=true pull --rebase origin main 2>&1 | tail -3 && git push origin main && echo API_PUSH_OK && git log --oneline -2'],
  },
  'tienda-publish-front-push': {
    file: 'zsh',
    args: ['-ilc', 'cd ventago-app && rm -f .git/*.lock 2>/dev/null; npx eslint src/hooks/api/useShopStatus.ts src/views/products/list/components/ProductParentList.tsx src/views/products/list/components/DataConfig.tsx src/views/products/list/components/BasicDataCard.tsx src/views/products/list/ProductsView.tsx --fix 2>&1 | tail -10; echo "--RECHECK--" && npx eslint src/hooks/api/useShopStatus.ts src/views/products/list/components/ProductParentList.tsx src/views/products/list/components/DataConfig.tsx src/views/products/list/components/BasicDataCard.tsx src/views/products/list/ProductsView.tsx && echo LINT_OK && git add src/hooks/api/useShopStatus.ts src/views/products/list/components/ProductParentList.tsx src/views/products/list/components/DataConfig.tsx src/views/products/list/components/BasicDataCard.tsx src/views/products/list/ProductsView.tsx && git commit -m "feat(shop): 상품별 Tienda Web 게시 토글 — 폼 칩 + madre 목록 Web 컬럼 (tienda 활성 매장만)" -m "Co-Authored-By: Claude <noreply@anthropic.com>" && git push origin main && echo FRONT_PUSH_OK && git log --oneline -1'],
  },
  // [Wave 1 2026-07-27] DB 정합성·보안·성능 백엔드 — eslint fix + tsc 게이트 후 선별 커밋·push
  // afip-issuer.service.ts(미커밋 WIP)는 add 목록에 없음 — 절대 포함 금지
  'wave1-api-deploy-push': {
    file: 'zsh',
    args: ['-ilc', 'cd api-ventago && rm -f .git/*.lock 2>/dev/null; F="src/app/users/users.model.ts src/app/users/users.service.ts src/app/users/user-function/user-function.service.ts src/app/auth/auth.service.ts src/app/auth/strategies/jwt.strategy.ts src/app/auth/guards/function-permission.guard.ts src/app/auth/guards/function-permission.guard.spec.ts src/app/mobile/auth/mobile-auth.service.ts src/app/caja-fuerte/caja-fuerte.service.ts src/app/sales/sales-create.service.ts src/app/role/role-function/role-function.service.ts src/app/role/role-function/role-function.service.spec.ts"; npx eslint ${=F} --fix 2>&1 | tail -12; echo "--LINT-INFO(레거시 any 오류는 비차단)--"; npx eslint ${=F} 2>&1 | tail -3; npx tsc --noEmit -p tsconfig.build.json && echo TSC_OK && git add ${=F} migrations/2026-07-27-hot-fk-indexes.sql && git commit -m "feat(core): Wave1 DB 정합성·보안·성능 — 민감컬럼 defaultScope 제외 + JWT/권한 캐시 + 재고 원자화 + nullify 재고복원 픽스 + 채번 sargable" -m "Phase63 B-0 advisory lock 채번(sales-create) 및 auth 구조 캐시 포함. 마이그레이션(핫패스 인덱스 36개+중복 DROP)은 로컬/운영 기적용." -m "Co-Authored-By: Claude <noreply@anthropic.com>" && git push origin main && echo API_PUSH_OK && git log --oneline -1'],
  },
  // [Wave 1] daily_number unique 인덱스 — 로컬(5432) 적용 + 마이그 파일 커밋·push
  'dn-unique-local-apply': {
    file: 'zsh',
    args: ['-ilc', 'psql -p 5432 -d ventago -v ON_ERROR_STOP=1 -f api-ventago/migrations/2026-07-26-phase63-daily-number-unique.sql && echo LOCAL_APPLIED && cd api-ventago && rm -f .git/*.lock 2>/dev/null; git add migrations/2026-07-26-phase63-daily-number-unique.sql && git commit -m "chore(db): Phase63 B-0 daily_number UNIQUE 부분 인덱스 마이그레이션 (중복 재배정 + 전기간 유니크)" -m "Co-Authored-By: Claude <noreply@anthropic.com>" && git push origin main && echo MIG_PUSH_OK'],
  },
  'wave1-root-docs-push': {
    file: 'zsh',
    args: ['-ilc', 'rm -f .git/*.lock 2>/dev/null; git add docs/db-risk-analysis-20260727.md .gsd/spec-wave1-db-integrity.md tools/agent-runner-jobs.js && git commit -m "docs(db): 운영 DB 위험 분석 리포트 + Wave1 SPEC" -m "Co-Authored-By: Claude <noreply@anthropic.com>" && git push origin main && echo ROOT_PUSH_OK && git log --oneline -1'],
  },
};
