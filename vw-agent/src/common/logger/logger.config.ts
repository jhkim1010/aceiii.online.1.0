// vw-agent 전용 Winston 로거 설정
// api-ventago 의 logger.config.ts 와 동일한 DailyRotate 패턴을 사용하되,
// 내부용 로그는 자체 logs/ 디렉토리에 분리 저장한다.
import { WinstonModuleOptions, utilities as nestWinstonModuleUtilities } from 'nest-winston';
import * as winston from 'winston';
import DailyRotateFile = require('winston-daily-rotate-file');

// ---------- 공통 포맷 ----------
const textFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.splat(),
  winston.format.printf(({ timestamp, level, message, context, stack }) => {
    const ctx = context ? `[${context as string}] ` : '';
    const stk = stack ? `\n${stack as string}` : '';

    return `${timestamp as string} [${level}] ${ctx}${message as string}${stk}`;
  }),
);

// ---------- Transports ----------
function buildTransports(): winston.transport[] {
  const logDir = process.env.VW_LOG_DIR || './logs';
  const isProd = process.env.NODE_ENV === 'production';

  return [
    // 콘솔 (개발 편의 위해 컬러)
    new winston.transports.Console({
      level: isProd ? 'info' : 'debug',
      format: winston.format.combine(
        winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        winston.format.colorize({ all: true }),
        nestWinstonModuleUtilities.format.nestLike('vw-agent', {
          prettyPrint: true,
          colors: true,
        }),
      ),
    }),
    // 전체 로그 (14일 보관, 파일당 20MB)
    new DailyRotateFile({
      dirname: logDir,
      filename: 'combined-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      zippedArchive: true,
      maxSize: '20m',
      maxFiles: '14d',
      level: 'info',
      format: textFormat,
    }),
    // 에러 로그만 별도 (30일 보관)
    new DailyRotateFile({
      dirname: logDir,
      filename: 'error-%DATE%.log',
      datePattern: 'YYYY-MM-DD',
      zippedArchive: true,
      maxSize: '20m',
      maxFiles: '30d',
      level: 'error',
      format: textFormat,
    }),
  ];
}

export const winstonConfig: WinstonModuleOptions = {
  transports: buildTransports(),
};
