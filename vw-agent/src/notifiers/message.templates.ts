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

export function formatHeartbeat(uptime: string, stats: Record<string, unknown>): string {
  const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
  const lines = Object.entries(stats).map(
    ([k, v]) => `  • ${escapeMd(k)}: ${escapeMd(String(v))}`,
  );

  return [
    `💚 *vw\\-agent heartbeat*`,
    `🕒 ${escapeMd(ts)}`,
    `⏱ uptime: ${escapeMd(uptime)}`,
    '',
    '📊 *상태*',
    lines.join('\n'),
  ].join('\n');
}

export function formatStartup(version: string, env: string): string {
  return [
    `🟢 *vw\\-agent 기동 완료*`,
    `version: ${escapeMd(version)}`,
    `env: ${escapeMd(env)}`,
  ].join('\n');
}
