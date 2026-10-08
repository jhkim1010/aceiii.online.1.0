# ventaGO AI 고객센터 + 자동 개발 시스템 구축 가이드

> 출처: 사용자가 2026-10-08 대화로 전달한 원문 (Phase 100 의 출발 자료). 링크 favicon 조각만 제거했다.
> 현재 코드·운영 규칙과의 대조는 `100-PREP.md`.

현재 사용하시는 NestJS + PostgreSQL + Ubuntu 환경을 중심으로, WhatsApp 고객 상담과 Telegram 개발 명령을 하나의 시스템으로 통합하는 방법을 설명하겠습니다.

목표는 단순한 AI 챗봇이 아닙니다. 고객의 문제를 접수하고, ventaGO의 실제 데이터와 서버 로그를 분석한 뒤, 필요하면 Codex가 소스코드를 수정하고 테스트까지 수행하는 AI 기술지원 및 개발 자동화 시스템입니다.

## 1. 전체 아키텍처

- WhatsApp Business — 고객 · 스페인어 상담 · 텍스트 / 음성 메시지
- Telegram Bot — 관리자 · 개발 명령 · 승인 / 상태 확인
- NestJS API Gateway — Webhook · 인증 · 요청 검증
- AI Support Orchestrator — 고객 식별 · AI 상담 · 장애 분류 · 로그 조회 · 티켓 생성 · 업무 전달
- PostgreSQL — 고객·상담·티켓·작업 이력
- Redis + BullMQ — 작업 큐·재시도·순서 관리
- Codex Worker (Docker) — Git 작업 브랜치 → AI 코드 수정 → 테스트
- GitHub Pull Request — 관리자 검토 · 승인 · 배포

설계 원칙: 고객이 사용하는 ventaGO 운영 서버와 Codex가 코드를 수정하는 개발 서버를 분리합니다. AI가 실수해도 실제 판매, 재고, 생산 데이터에 영향을 주지 않도록 만드는 것이 가장 중요합니다.

## 2. 시스템을 구성하는 서비스

| 서비스 | 기술 | 담당 기능 |
|---|---|---|
| `support-api` | NestJS | WhatsApp·Telegram Webhook |
| `support-ai` | OpenAI API | 스페인어 상담 및 문제 분류 |
| `support-db` | PostgreSQL | 고객·티켓·작업 이력 |
| `support-queue` | BullMQ + Redis | 비동기 처리 |
| `support-worker` | Node.js | 상담 처리·진단 |
| `codex-worker` | Docker + Codex CLI | 코드 수정·테스트 |
| `git-integration` | GitHub API | PR 생성 및 결과 조회 |

처음에는 `support-api`와 `support-worker`를 같은 NestJS 프로젝트에서 시작해도 됩니다. Codex Worker만 별도 컨테이너 또는 서버로 분리하는 것이 좋습니다.

## 3. PostgreSQL 데이터베이스 설계

기존 ventaGO 운영 DB에 직접 고객지원 테이블을 추가하기보다는 `ventago_support`라는 별도 DB를 만드는 것을 권합니다.

```sql
CREATE DATABASE ventago_support;
```

① 고객 상담 및 장애 티켓

```sql
CREATE TABLE support_tickets (
  id BIGSERIAL PRIMARY KEY,
  company_id INTEGER NOT NULL,
  customer_phone VARCHAR(30),
  source VARCHAR(20) NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  severity VARCHAR(20) DEFAULT 'normal',
  status VARCHAR(30) DEFAULT 'open',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

② WhatsApp 대화 이력

```sql
CREATE TABLE support_messages (
  id BIGSERIAL PRIMARY KEY,
  ticket_id BIGINT REFERENCES support_tickets(id),
  provider_message_id TEXT UNIQUE,
  direction VARCHAR(10) NOT NULL,
  message_type VARCHAR(20) NOT NULL,
  content TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

③ AI 코드 수정 작업

```sql
CREATE TABLE ai_code_jobs (
  id BIGSERIAL PRIMARY KEY,
  ticket_id BIGINT REFERENCES support_tickets(id),
  instruction TEXT NOT NULL,
  status VARCHAR(30) DEFAULT 'pending',
  branch_name TEXT,
  pr_url TEXT,
  result_summary TEXT,
  approved_by BIGINT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

④ 감사 로그

```sql
CREATE TABLE ai_audit_logs (
  id BIGSERIAL PRIMARY KEY,
  job_id BIGINT REFERENCES ai_code_jobs(id),
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

실제 운영 버전에는 고객 식별용 `contacts`, 매장별 인증 정보, 메시지 보존 정책, 작업 승인 상태 전이, 외부 이벤트 중복 방지 인덱스도 추가해야 합니다.

## 4. NestJS 프로젝트 구성

```bash
nest new ventago-ai-support
cd ventago-ai-support

npm install @nestjs/config @nestjs/axios
npm install @nestjs/bullmq bullmq ioredis
npm install pg
npm install openai
npm install axios
```

```
ventago-ai-support/
├── src/
│   ├── whatsapp/        (whatsapp.controller.ts, whatsapp.service.ts)
│   ├── telegram/        (telegram.controller.ts, telegram.service.ts)
│   ├── ai/              (ai-support.service.ts, diagnosis.service.ts)
│   ├── tickets/         (tickets.service.ts, tickets.repository.ts)
│   ├── codex/           (codex.processor.ts, codex-runner.service.ts)
│   ├── queue/
│   ├── security/
│   └── main.ts
├── docker/
├── .env
└── package.json
```

## 5. WhatsApp Business API 연결

Meta의 공식 WhatsApp Cloud API를 사용하는 것이 좋습니다. 비공식 WhatsApp Web 자동화 라이브러리는 고객지원용 핵심 인프라로 추천하지 않습니다.

준비할 항목은 Meta Business Portfolio, WhatsApp Business Account, 전화번호 ID, 시스템 사용자 액세스 토큰, 앱 시크릿입니다.

### 환경변수

```
WHATSAPP_TOKEN=your_access_token
WHATSAPP_PHONE_ID=your_phone_number_id
WHATSAPP_VERIFY_TOKEN=your_verify_token
WHATSAPP_APP_SECRET=your_meta_app_secret
WHATSAPP_API_VERSION=vXX.X

TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_ADMIN_CHAT_ID=your_chat_id
TELEGRAM_WEBHOOK_SECRET=your_secret

DATABASE_URL=postgresql://...
REDIS_URL=redis://redis:6379
OPENAI_API_KEY=your_openai_key
```

`WHATSAPP_API_VERSION`에는 Meta가 현재 지원하는 Graph API 버전을 지정합니다.

### WhatsApp Webhook 예제

```ts
import {
  Controller, Get, Post, Query, Req,
  Res, HttpCode, ForbiddenException
} from '@nestjs/common';
import { Request, Response } from 'express';
import { createHmac, timingSafeEqual } from 'crypto';
import { WhatsAppService } from './whatsapp.service';

@Controller('webhooks/whatsapp')
export class WhatsAppController {
  constructor(private readonly service: WhatsAppService) {}

  @Get()
  verify(@Query() query: Record<string, string>, @Res() res: Response) {
    const valid =
      query['hub.mode'] === 'subscribe' &&
      query['hub.verify_token'] === process.env.WHATSAPP_VERIFY_TOKEN;

    if (!valid) return res.sendStatus(403);

    return res.status(200).send(query['hub.challenge']);
  }

  @Post()
  @HttpCode(200)
  async receive(@Req() req: Request) {
    const raw = req.body as Buffer;
    const signature = req.header('x-hub-signature-256') ?? '';

    const expected = 'sha256=' + createHmac('sha256', process.env.WHATSAPP_APP_SECRET!)
      .update(raw).digest('hex');

    const a = Buffer.from(signature);
    const b = Buffer.from(expected);

    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new ForbiddenException();
    }

    await this.service.enqueueWebhook(JSON.parse(raw.toString('utf8')));

    return 'OK';
  }
}
```

이 예제는 Express 기반 NestJS에서 해당 경로의 요청 본문을 원본 `Buffer`로 받을 수 있도록 설정했다는 전제입니다. `express.raw()`를 경로에 적용하거나 NestJS의 `rawBody` 옵션을 적절히 구성해야 합니다.

`enqueueWebhook()`은 수신 메시지를 DB에 중복 없이 기록하고 BullMQ에 작업을 등록하는 함수로 구현합니다. 외부 API의 재전송 가능성을 고려하여 메시지 ID를 기준으로 중복 처리하지 않도록 해야 합니다.

Meta Webhook 서명 검증에는 `X-Hub-Signature-256`과 앱 시크릿을 사용합니다.

### AI의 스페인어 응답

고객: «No puedo imprimir la factura desde ventaGO.»

AI는 인증된 매장 정보, 프린터 설정, 기존 해결 문서 등을 확인한 후 답변합니다:
«Entiendo. ¿El problema ocurre con todas las facturas o solamente con una venta específica?»

기존에 해결한 문제라면 단계별로 안내합니다. 새로운 오류라면 티켓을 만들고 Telegram으로 전달합니다.

음성 메시지는 WhatsApp에서 미디어 ID를 받은 뒤, 파일을 내려받아 음성 인식 API로 텍스트화하고 동일한 상담 처리 과정에 넣으면 됩니다.

## 6. Telegram Bot 연결

`@BotFather` → `/newbot` 으로 Bot 생성, Bot Token 을 서버에 등록.

| 명령 | 기능 |
|---|---|
| `/tickets` | 미해결 고객 장애 조회 |
| `/ticket 1042` | 특정 장애 상세 조회 |
| `/analyze 1042` | AI 원인 분석 |
| `/fix 1042` | Codex 코드 수정 작업 시작 |
| `/status 1042` | 작업 진행 상황 |
| `/cancel 1042` | 대기 중 작업 취소 |

Telegram Webhook은 `secret_token`으로 요청 출처를 검증할 수 있으며, 메시지와 버튼 이벤트를 모두 받을 수 있습니다.

### Telegram 명령 처리 예제

```ts
import { Controller, Post, Req, Headers, ForbiddenException } from '@nestjs/common';
import { Request } from 'express';
import { TicketsService } from '../tickets/tickets.service';

@Controller('webhooks/telegram')
export class TelegramController {
  constructor(private readonly tickets: TicketsService) {}

  @Post()
  async receive(
    @Req() req: Request,
    @Headers('x-telegram-bot-api-secret-token') secret: string,
  ) {
    if (secret !== process.env.TELEGRAM_WEBHOOK_SECRET) {
      throw new ForbiddenException();
    }

    const update = req.body;
    const msg = update.message;

    if (!msg?.text) return { ok: true };

    const allowedChat = String(msg.chat.id) === process.env.TELEGRAM_ADMIN_CHAT_ID;

    if (!allowedChat) {
      throw new ForbiddenException();
    }

    const match = msg.text.match(/^\/fix(?:@\w+)?\s+(\d+)$/);

    if (match) {
      await this.tickets.requestCodeFix(Number(match[1]), msg.from.id);
    }

    return { ok: true };
  }
}
```

여기서 `requestCodeFix()`는 즉시 운영 코드를 수정하는 함수가 아니라, 승인된 관리자 명령을 검증하고 작업을 큐에 넣는 함수입니다.

실제 운영에서는 Telegram 사용자 ID까지 허용 목록으로 검증하고, 업데이트 ID 중복 방지, 명령별 권한, 작업 상태 검증을 추가해야 합니다.

## 7. Codex가 자동으로 코드를 수정하도록 연결하기

Codex CLI에는 스크립트나 CI 환경에서 실행할 수 있는 `codex exec` 명령이 있습니다. `--sandbox workspace-write`를 이용한 작업 공간 내 수정 방식을 지원합니다.

```bash
npm install -g @openai/codex

git clone git@github.com:YOUR_ORG/ventago.git /workspace/job-1042
cd /workspace/job-1042
git checkout -b ai/fix-1042

codex exec \
  --sandbox workspace-write \
  --cd /workspace/job-1042 \
  "Analyze ticket 1042.

  Problem:
  Error 500 when closing cash register.

  Requirements:
  1. Find the root cause.
  2. Make the smallest safe code change.
  3. Add regression tests.
  4. Do not modify production data.
  5. Do not change database schema.
  6. Summarize the changes in Spanish."

npm run lint
npm run build
npm test
```

테스트가 성공하면 해당 브랜치를 GitHub로 푸시하고 Pull Request를 생성합니다. 이 단계의 Git 권한은 해당 저장소와 브랜치로 제한하고, PR 병합 및 배포 권한은 별도로 관리합니다.

주의: `codex exec`의 프롬프트만으로 보안을 보장할 수는 없습니다. 실제 제한은 Docker 격리, 파일 접근 권한, 네트워크 제한, DB 계정 권한, GitHub 권한으로 강제해야 합니다.

## 8. 자동화 작업의 상태 관리

1. NEW — 고객 장애 접수: WhatsApp 상담 내용 저장 및 티켓 생성
2. TRIAGED — AI 분석: 매장, 기능, 오류 유형, 긴급도 분류
3. AWAITING_APPROVAL — 관리자 확인: Telegram에서 코드 수정 승인
4. CODING — Codex 작업 중: 별도 Git 브랜치에서 수정
5. TESTING — 자동 테스트: 빌드, 단위 테스트, 회귀 테스트
6. REVIEW — Pull Request 생성: Telegram으로 변경 내용과 테스트 결과 전송
7. DEPLOYED — 배포 완료: 승인된 변경 사항 배포 후 고객에게 안내

Codex가 작업에 실패하면 실패 로그와 원인을 티켓에 남기고, 재시도 여부를 관리자가 결정하도록 구성합니다. 무한 재시도는 피해야 합니다.

## 9. Telegram에서 실제로 보게 될 화면 (예시)

```
ventaGO AI Developer
🔧 Ticket #1042
Cliente: Inquieta   Problema: Error 500 en cierre de caja
Estado: Análisis completado   Causa probable: Manejo incorrecto de valores NULL
Codex propone: Revisar `caja.service.ts` y agregar pruebas de regresión.
[Aprobar fix] [Rechazar]
```

수정이 완료되면 Telegram으로 PR 링크, 변경된 파일 목록, 테스트 결과, 위험도와 배포 승인 버튼을 보냅니다.

## 10. ventaGO에 특별히 추가하면 좋은 기능

| 기능 | 기대 효과 |
|---|---|
| 매장별 장애 감지 | 동일한 오류가 여러 매장에서 발생하는지 확인 |
| PostgreSQL 읽기 전용 진단 | 실제 판매·재고 데이터를 변경하지 않고 문제 분석 |
| 프린터 설정 진단 | Epson, POS 프린터 연결 문제 분류 |
| 버전별 장애 추적 | 특정 업데이트 이후 발생한 오류 파악 |
| 기존 해결 사례 검색 | AI가 코드 수정 없이 즉시 해결 |
| 배포 후 모니터링 | 수정 이후 같은 오류가 재발하는지 감시 |

ventaGO에서는 고객의 문제를 모두 코드 버그로 간주하지 않는 것이 중요합니다. 프린터가 작동하지 않는다면 AI가 먼저 프린터 설정, Windows 인쇄 서비스, 네트워크 연결을 확인해야 합니다. 코드 수정은 실제 프로그램 결함으로 판단될 때만 시작합니다.

## 11. 실제 구축 순서

- 1주 차 — WhatsApp + Telegram: 메시지 수신, 스페인어 AI 상담, PostgreSQL 티켓 저장, Telegram 알림
- 2주 차 — ventaGO 진단 연동: 매장 인증, 오류 로그 조회, 버전 확인, 기존 해결 사례 검색
- 3주 차 — Codex 자동 수정: Telegram 명령으로 Docker Worker 실행, 코드 수정, 자동 테스트, PR 생성
- 4주 차 — 운영 안정화: 권한 관리, 실패 복구, 승인 흐름, 고객 정보 보호, 배포 후 모니터링

이 일정은 개발 환경과 GitHub 저장소가 준비되어 있고 WhatsApp Business API 등록이 원활하다는 가정의 초기 MVP 목표입니다.

## 다음 단계

Docker Compose, NestJS 소스, PostgreSQL 마이그레이션, WhatsApp Webhook, Telegram Bot, Codex Worker를 포함한 실행 가능한 프로젝트로 발전.

설치 위치 질문: AI 고객지원 시스템을 어디에 설치하시겠습니까? → 가이드의 추천: **별도의 Ubuntu 서버**.
