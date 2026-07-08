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

  // 에이전트 릴리즈 태그 push — GitHub Actions 빌드 트리거. arg = 태그명
  // (태그 자체는 Claude 가 로컬 생성 — 샌드박스에는 GitHub 자격증명이 없어 push 만 위임)
  'push-agent-tag': {
    file: 'git',
    args: (arg) => {
      if (!/^(print|zebra)-agent-v\d+\.\d+\.\d+$/.test(arg || '')) throw new Error('arg 는 (print|zebra)-agent-vX.Y.Z 태그명이어야 함');

      return ['push', 'origin', arg];
    },
  },
};
