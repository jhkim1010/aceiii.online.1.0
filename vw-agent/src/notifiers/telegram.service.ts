// Telegram Bot 알림 송신 서비스
// ----------------------------------------------------------------------------
// - polling=false (one-way 송신만 — M3 부터 승인 버튼 위해 enable 예정)
// - silent 옵션으로 heartbeat 는 무알림 송신
// - 송신 실패 시 SQLite events.notified_at 갱신 보류 + 다음 루프 재시도
// ----------------------------------------------------------------------------
import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import TelegramBot from 'node-telegram-bot-api';

import type { Env } from '../config/env.schema';

import {
  AlertParams,
  DailyReportData,
  formatAlert,
  formatDailyReport,
  formatStartup,
} from './message.templates';

export interface SendOptions {
  silent?: boolean;
}

@Injectable()
export class TelegramService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TelegramService.name);
  private bot: TelegramBot | null = null;
  private chatId = '';

  constructor(@Inject(ConfigService) private readonly config: ConfigService<Env, true>) {}

  onModuleInit(): void {
    const token = this.config.get('TELEGRAM_BOT_TOKEN', { infer: true });
    this.chatId = this.config.get('TELEGRAM_CHAT_ID', { infer: true });

    // polling false — M1 은 송신 전용
    this.bot = new TelegramBot(token, { polling: false });
    this.logger.log(`Telegram bot 초기화 (chat_id=${this.chatId})`);
  }

  onModuleDestroy(): void {
    // node-telegram-bot-api 는 polling=false 면 별도 close 불필요
    this.bot = null;
  }

  async sendAlert(params: AlertParams, opts: SendOptions = {}): Promise<boolean> {
    const text = formatAlert(params);

    return this.send(text, opts);
  }

  async sendDailyReport(data: DailyReportData): Promise<boolean> {
    const text = formatDailyReport(data);

    return this.send(text, { silent: true });
  }

  async sendStartup(version: string, env: string): Promise<boolean> {
    const text = formatStartup(version, env);

    return this.send(text, { silent: true });
  }

  private async send(text: string, opts: SendOptions): Promise<boolean> {
    if (!this.bot) {
      this.logger.warn('Telegram bot 미초기화 — 송신 스킵');

      return false;
    }

    try {
      await this.bot.sendMessage(this.chatId, text, {
        parse_mode: 'MarkdownV2',
        disable_notification: opts.silent ?? false,
      });

      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`Telegram 송신 실패: ${msg}`);

      return false;
    }
  }
}
