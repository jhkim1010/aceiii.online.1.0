// Telegram 메시지 템플릿 — Markdown V2 호환
// ----------------------------------------------------------------------------
// 모든 템플릿은:
// - 시작에 severity emoji 1개 (info/warn/critical)
// - 첫 줄: rule_id + 짧은 제목
// - 둘째 줄: 발생시각
// - 본문: 사람이 즉시 행동 가능한 형태
// ----------------------------------------------------------------------------

export type Severity = 'info' | 'warn' | 'critical';

const SEVERITY_EMOJI: Record<Severity, string> = {
  info: 'ℹ️',
  warn: '⚠️',
  critical: '🚨',
};

/** Telegram MarkdownV2 특수문자 이스케이프 */
export function escapeMd(text: string): string {
  return text.replace(/([_*[\]()~`>#+\-=|{}.!\\])/g, '\\$1');
}

export interface AlertParams {
  ruleId: string;
  severity: Severity;
  title: string;
  detail: string;
  context?: Record<string, unknown>;
}

export function formatAlert(params: AlertParams): string {
  const { ruleId, severity, title, detail, context } = params;
  const emoji = SEVERITY_EMOJI[severity];
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);

  const head = `${emoji} *${escapeMd(ruleId)}* ${escapeMd(title)}`;
  const time = `🕒 ${escapeMd(ts)} \\(UTC\\)`;
  const body = escapeMd(detail);

  let ctxBlock = '';
  if (context && Object.keys(context).length > 0) {
    const lines = Object.entries(context).map(
      ([k, v]) => `  • ${escapeMd(k)}: ${escapeMd(String(v))}`,
    );
    ctxBlock = `\n📋 *컨텍스트*\n${lines.join('\n')}`;
  }

  return `${head}\n${time}\n\n${body}${ctxBlock}`;
}

// formatHeartbeat 는 2026-04-23 개편으로 제거됨 — 일일 리포트(formatDailyReport)로 대체
// 과거 이력: 30분마다 setInterval 로 무조건 송신 → noise 과다 → 매일 09:00 KST 1회로 전환

export interface DailyReportData {
  /** 현재 KST 시각 문자열 (예: "2026-04-24 09:00:00") */
  nowKst: string;
  /** 사람이 읽을 수 있는 uptime 문자열 (예: "1d 2h 15m") */
  uptime: string;
  /** 지난 24시간 severity 별 이벤트 수 */
  severityCounts: { critical: number; warn: number; info: number };
  /** 지난 24시간 규칙별 이벤트 수 (count 내림차순) */
  byRule: Array<{ ruleId: string; count: number; severities: string[] }>;
  /** PG pool 상태 (totalCount/idleCount/waitingCount/max) */
  pgPool: { total: number; idle: number; waiting: number; max: number };
  /** 프로세스 메모리 RSS (MB) */
  memoryRssMb: number;
}

/** 매일 아침 09:00 KST 에 보내는 일일 리포트 */
export function formatDailyReport(r: DailyReportData): string {
  const { nowKst, uptime, severityCounts: sev, byRule, pgPool, memoryRssMb } = r;

  const severityLines = [
    `  • critical: ${sev.critical}건`,
    `  • warn: ${sev.warn}건`,
    `  • info: ${sev.info}건`,
  ]
    .map((l) => escapeMd(l))
    .join('\n');

  // 규칙별 집계 — 비어있을 때는 안내 문구
  let ruleBlock: string;
  if (byRule.length === 0) {
    ruleBlock = escapeMd('  • (이벤트 없음 — 조용한 하루였음)');
  } else {
    ruleBlock = byRule
      .map((r2) => {
        const sevStr = r2.severities.length > 0 ? ` \\(${escapeMd(r2.severities.join(','))}\\)` : '';

        return `  • ${escapeMd(r2.ruleId)}: ${r2.count}건${sevStr}`;
      })
      .join('\n');
  }

  const poolLine = escapeMd(
    `🔌 PG pool: total ${pgPool.total}/${pgPool.max}, idle ${pgPool.idle}, waiting ${pgPool.waiting}`,
  );
  const memLine = escapeMd(`🧠 memory: ${memoryRssMb} MB`);

  return [
    `💚 *vw\\-agent 일일 리포트*`,
    `🕒 ${escapeMd(nowKst)} \\(KST\\)`,
    `⏱ uptime: ${escapeMd(uptime)}`,
    '',
    `📊 *지난 24시간 이벤트*`,
    severityLines,
    '',
    `📋 *규칙별 발생*`,
    ruleBlock,
    '',
    poolLine,
    memLine,
  ].join('\n');
}

export function formatStartup(version: string, env: string): string {
  return [
    `🟢 *vw\\-agent 기동 완료*`,
    `version: ${escapeMd(version)}`,
    `env: ${escapeMd(env)}`,
  ].join('\n');
}
