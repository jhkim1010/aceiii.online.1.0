# CODEX manual review — Phase 98-10 (api-ventago)

## Round 1 (before fixes)
```
Reading additional input from stdin...
2026-10-05T00:34:27.240993Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a1097b-c0c9-7800-989e-e19f631fefa0
--------
user
git 명령을 실행하지 마라. diff 를 보지 마라. 아래 4개 파일만 읽고 Phase98-10 Watch(Wear OS) resumen 코드의 보안/정합성 결함을 찾아라(가드 재판정, D-15① favor 재배분, ingresos 제외 규칙). 파일: src/app/watch/watch-token.guard.ts, src/app/watch/resumen/watch-resumen.service.ts, src/app/watch/resumen/sources/pagos.source.ts, src/app/watch/resumen/sources/ingresos.source.ts. P1/P2/P3 로 등급을 매겨라.
codex
지정한 4개 파일만 읽고, git/diff 없이 가드 재판정·D-15① favor 재배분·ingresos 제외 규칙을 중심으로 결함을 분류하겠습니다.
exec
/bin/zsh -lc "sed -n '1,240p' src/app/watch/watch-token.guard.ts && sed -n '1,320p' src/app/watch/resumen/watch-resumen.service.ts && sed -n '1,280p' src/app/watch/resumen/sources/pagos.source.ts && sed -n '1,280p' src/app/watch/resumen/sources/ingresos.source.ts" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
 succeeded in 0ms:
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { WatchDevice } from './watch-device.model';
import { hashWatchSecret, isWatchDeviceUsable } from './watch-token.util';
import { loadUserWithStoreRoles } from '../auth/store-filtered-roles';
import { TenantContext } from 'src/common/tenant/tenant-context';

// =============================================================================
// [Phase 98-02, D-05, T-98-10~T-98-15] 워치 토큰 가드
// =============================================================================
// Passport 기반 가드 클래스를 상속하지 않는다 — 전역 JwtGlobalGuard 가 채운 request.user 를
// 뒤 가드가 지우는 사고를 재발시키지 않기 위해서다(memory:
// route-guard-undoes-global-guard-user). 이 가드는 @Public() 라우트에서 자기
// 완결적으로 인증·인가·테넌트 확정을 전부 한다.
//
// 매 요청 재판정(D-05): 토큰이 살아 있어도 그 사용자가 "지금" admin 이 아니거나
// 매장이 바뀌었으면 401 이다. 98-01 CODEX P1 이 지적한 "claim 시점에 admin 이었다"
// 와 "poll 시점에 admin 이다" 사이의 ms 창은 poll 이 이미 닫았지만, 그 뒤 임의의
// 시점에 권한이 회수되는 긴 창은 이 가드의 매 요청 재판정이 닫는다.
//
// 401 메시지는 모든 거절 경우 동일하다 — 어느 조건이 실패했는지 외부에 드러내면
// 그 자체가 추측 정보가 된다(T-98-15). 서버 로그에는 조건을 구분할 수 있는
// deviceId 만 남긴다 — 토큰·해시는 로그에 쓰지 않는다(D-14 ③).
// =============================================================================

const WATCH_TOKEN_HEADER = 'x-watch-token';
const WATCH_TOKEN_LENGTH = 43;
const UNUSABLE_MSG = 'Reloj no vinculado';
const ACTIVE_STATUSES = new Set(['active', 'trial']);

// sliding 갱신 — 10분 안의 재요청은 쓰지 않는다(T-98-18, DB 부하 방지).
const SLIDING_REFRESH_THRESHOLD_MS = 10 * 60 * 1000;
const WATCH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90일(sliding)

export interface WatchGuardUser {
  id: number;
  storeId: number;
  branchId: number | null;
  roles: string[];
}

/** 이 가드가 읽고/쓰는 request 모양만 — 나머지 필드는 알 필요 없다(unsafe-any 방지). */
interface WatchGuardRequest {
  headers?: Record<string, unknown>;
  user?: WatchGuardUser;
  watchDevice?: WatchDevice;
}

@Injectable()
export class WatchTokenGuard implements CanActivate {
  private readonly logger = new Logger(WatchTokenGuard.name);

  constructor(
    @InjectModel(WatchDevice)
    private readonly watchDeviceModel: typeof WatchDevice,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<WatchGuardRequest>();
    // x-watch-token 헤더만 읽는다 — query/body 는 절대 보지 않는다(T-98-14).
    const header = request.headers?.[WATCH_TOKEN_HEADER];

    if (typeof header !== 'string' || header.length !== WATCH_TOKEN_LENGTH) {
      throw new UnauthorizedException(UNUSABLE_MSG);
    }

    const tokenHash = hashWatchSecret(header);
    const device = await this.watchDeviceModel.findOne({
      where: { tokenHash },
    });
    const now = new Date();

    if (!device || !isWatchDeviceUsable(device, now)) {
      this.logger.warn(
        `[WATCH] 토큰 사용 불가 — device=${device?.id ?? 'unknown'}`,
      );
      throw new UnauthorizedException(UNUSABLE_MSG);
    }

    // D-05 — 매 요청마다 현재 역할·매장을 다시 읽는다. 토큰을 자동 회수하지
    // 않는다(역할이 돌아오면 다시 쓸 수 있어야 하고, "즉시 401" 은 이 재판정으로
    // 이미 충족된다).
    const resolved = await loadUserWithStoreRoles(device.userId);

    if (
      !resolved ||
      !ACTIVE_STATUSES.has(resolved.user.status) ||
      resolved.user.storeId !== device.storeId ||
      !resolved.roles.includes('admin')
    ) {
      this.logger.warn(
        `[WATCH] 역할·매장 재판정 실패 — device=${device.id} userId=${device.userId}`,
      );
      throw new UnauthorizedException(UNUSABLE_MSG);
    }

    TenantContext.resolve({
      storeId: device.storeId,
      isSuperAdmin: false,
      userId: resolved.user.id,
    });

    // fail-closed 사후 확인 — resolve() 는 컨텍스트가 없으면 조용히 무시하므로
    // 예외 없이도 미해석으로 남을 수 있다.
    const ctx = TenantContext.get();
    if (!ctx?.resolved || typeof ctx.storeId !== 'number') {
      this.logger.error(
        `[WATCH] TenantContext 확정 실패 — device=${device.id}`,
      );
      throw new ForbiddenException(UNUSABLE_MSG);
    }

    const guardUser: WatchGuardUser = {
      id: resolved.user.id,
      storeId: device.storeId,
      branchId: resolved.user.branchId ?? null,
      roles: resolved.roles,
    };
    request.user = guardUser;
    request.watchDevice = device;

    this.refreshSliding(device, now);

    return true;
  }

  /**
   * sliding 만료 갱신 — lastSeenAt 이 없거나 10분 넘게 지났을 때만 쓴다.
   * 실패해도 요청을 막지 않는다(커밋 후 실패가 응답을 바꾸지 않는다는 원칙과
   * 같은 취지 — 이미 가드를 통과한 요청을 갱신 실패로 되돌리지 않는다).
   */
  private refreshSliding(device: WatchDevice, now: Date): void {
    const lastSeen = device.lastSeenAt?.getTime() ?? 0;
    if (now.getTime() - lastSeen <= SLIDING_REFRESH_THRESHOLD_MS) return;

    device
      .update({
        lastSeenAt: now,
        expiresAt: new Date(now.getTime() + WATCH_TOKEN_TTL_MS),
      })
      .catch((err: Error) => {
        this.logger.error(
          `[WATCH] sliding 갱신 실패 — device=${device.id}: ${err.message}`,
        );
      });
  }
}
import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Sequelize } from 'sequelize';
import { MemoryCacheService } from 'src/common/cache/memory-cache.service';
import { storeKey } from 'src/common/cache/cache-key';
import { DEFAULT_STORE_TZ } from 'src/common/constants/timezone';
import { buildSecciones, BranchRef } from './build-secciones';
import { storeClock } from './watch-clock.util';
import {
  SECTION_KEYS,
  SOURCE_KEYS,
  SourceCacheEntry,
  SourceKey,
  WATCH_RESUMEN_SCHEMA_VERSION,
  WATCH_SOURCES,
  WatchResumenV2,
  WatchSource,
  WatchStoreContext,
} from './watch-resumen.contract';

// =============================================================================
// [Phase 98-02, D-08·D-09] GET /watch/resumen 합성기.
// =============================================================================
// 인증·인가·테넌트 확정은 워치 토큰 가드가 끝낸다 — 이 서비스는 그 뒤에서
// storeId 로만 움직인다(모델 쿼리 금지 — @Public 라우트는 테넌트 훅이 no-op 이므로
// raw SQL + :storeId 바인드만 쓴다, T-98-10).
//
// 캐시는 인가 **뒤**에만 있고 키에 사용자를 넣지 않는다 — admin 은 매장 전체를
// 보므로 매장 단위 결과가 사용자와 무관하게 같다.
//
// [98-10] D-15 ⑤ 지점 활성/비활성 구분 — `loadStoreContext()` 가 `branches.is_active`
// 를 읽어 `BranchRef.isActive` 로 넘긴다. 선택기(sucursales) 노출 판단은
// build-secciones.ts 가 한다(비활성 + 그날 ventas 행 없음 → 숨김). 이 서비스는
// 지점 목록을 활성 여부로 **필터하지 않는다** — `parseSucursal`(아래)과 모든 섹션의
// 원천 데이터(porSucursal·총계)는 활성 여부와 무관하게 전체 지점을 본다. 비활성
// 지점에 오늘 판매가 있으면 돈이 사라지면 안 되므로(narrowing-filter-must-never-widen
// 과 같은 원칙), 걸러내는 지점은 "선택기에 보이는가" 뿐이다.
// =============================================================================

const FINAL_CACHE_TTL_MS = 30_000;
const CTX_CACHE_TTL_MS = 60_000;

interface StoreContextRow {
  tienda: string;
  timezone: string | null;
}

interface BranchContextRow {
  id: number;
  name: string;
  is_active: boolean | null;
}

interface StoreContext {
  tienda: string;
  timezone: string;
  branches: BranchRef[];
}

@Injectable()
export class WatchResumenService {
  private readonly logger = new Logger(WatchResumenService.name);
  private readonly sourceByKey: Map<SourceKey, WatchSource>;

  constructor(
    @InjectConnection() private readonly sequelize: Sequelize,
    private readonly cache: MemoryCacheService,
    @Inject(WATCH_SOURCES) sources: WatchSource[],
  ) {
    const providedKeys = new Set(sources.map((s) => s.key));
    const missing = SOURCE_KEYS.filter((k) => !providedKeys.has(k));

    if (missing.length > 0) {
      // 부팅 실패 — 원천이 하나라도 빠진 채 배선되면 섹션이 조용히 비는 대신
      // 서버가 안 뜬다(98-10 이 6개를 전부 넘긴다).
      throw new Error(
        `WatchResumenService: WATCH_SOURCES 에 누락된 원천 — ${missing.join(', ')}`,
      );
    }

    this.sourceByKey = new Map(sources.map((s) => [s.key, s]));
  }

  async getResumen(
    user: {
      id: number;
      storeId: number;
      branchId: number | null;
      roles: string[];
    },
    rawSucursal: string | undefined,
    opts?: { now?: Date },
  ): Promise<WatchResumenV2> {
    const storeCtx = await this.loadStoreContext(user.storeId);
    const sucursalId = this.parseSucursal(rawSucursal, storeCtx.branches);

    const now = opts?.now ?? new Date();
    const clock = storeClock(now, storeCtx.timezone);
    const ctx: WatchStoreContext = {
      storeId: user.storeId,
      tz: clock.tzUsada,
      clock,
      user: { id: user.id, branchId: user.branchId, roles: user.roles },
    };

    const finalKey = storeKey(
      'watch:resumen',
      user.storeId,
      'v2',
      ctx.tz,
      String(sucursalId ?? 'all'),
      clock.hoy,
    );

    return this.cache.getOrLoad(
      finalKey,
      FINAL_CACHE_TTL_MS,
      () => this.assemble(ctx, storeCtx, sucursalId),
      {
        shouldCache: (value: WatchResumenV2) =>
          SECTION_KEYS.every((k) => value.secciones[k].status === 'ok'),
      },
    );
  }

  private async assemble(
    ctx: WatchStoreContext,
    storeCtx: StoreContext,
    sucursalId: number | null,
  ): Promise<WatchResumenV2> {
    const rows: Partial<Record<SourceKey, unknown[]>> = {};
    const failed = new Set<SourceKey>();
    const asOf: Record<SourceKey, string | null> = {
      ventas: null,
      pagos: null,
      gastos: null,
      ingresos: null,
      facturacion: null,
      cajas: null,
    };

    const results = await Promise.allSettled(
      SOURCE_KEYS.map((key) => this.loadSource(key, ctx)),
    );

    SOURCE_KEYS.forEach((key, i) => {
      const result = results[i];
      if (result.status === 'fulfilled') {
        rows[key] = result.value.rows;
        asOf[key] = result.value.asOf;
      } else {
        failed.add(key);
        this.logger.warn(
          `[WATCH] 원천 실패 — key=${key} storeId=${ctx.storeId}: ${
            (result.reason as Error)?.message ?? result.reason
          }`,
        );
      }
    });

    const built = buildSecciones({
      rows,
      failed,
      asOf,
      ctx,
      branches: storeCtx.branches,
      sucursalId,
    });

    return {
      schemaVersion: WATCH_RESUMEN_SCHEMA_VERSION,
      tienda: storeCtx.tienda,
      zona: ctx.tz,
      hoy: ctx.clock.hoy,
      generadoEn: new Date().toISOString(),
      ...built,
    };
  }

  private async loadSource(
    key: SourceKey,
    ctx: WatchStoreContext,
  ): Promise<SourceCacheEntry<unknown>> {
    // 생성자에서 전부 등록돼 있음을 이미 확인했다(부팅 검사) — 여기서는 단언만.
    const source = this.sourceByKey.get(key) as WatchSource;
    const periodoKey = source.periodo === 'mes' ? ctx.clock.mes : ctx.clock.hoy;
    const cacheKey = storeKey(
      'watch:resumen',
      ctx.storeId,
      'v2',
      ctx.tz,
      'all',
      key,
      periodoKey,
    );

    return this.cache.getOrLoad(cacheKey, source.ttlMs, async () => ({
      rows: await source.load(ctx),
      asOf: new Date().toISOString(),
    }));
  }

  private async loadStoreContext(storeId: number): Promise<StoreContext> {
    const key = storeKey('watch:ctx', storeId);

    return this.cache.getOrLoad(key, CTX_CACHE_TTL_MS, async () => {
      const storeRows = await this.sequelize.query<StoreContextRow>(
        `SELECT COALESCE(NULLIF(alias_name, ''), name) AS tienda, timezone
           FROM stores
          WHERE id = :storeId`,
        { replacements: { storeId }, type: QueryTypes.SELECT },
      );
      const branchRows = await this.sequelize.query<BranchContextRow>(
        `SELECT id, name, is_active
           FROM branches
          WHERE store_id = :storeId
          ORDER BY id`,
        { replacements: { storeId }, type: QueryTypes.SELECT },
      );

      const store = storeRows[0];

      return {
        tienda: store?.tienda ?? '',
        timezone: store?.timezone ?? DEFAULT_STORE_TZ,
        branches: branchRows.map((b) => ({
          id: b.id,
          nombre: b.name,
          isActive: b.is_active ?? true,
        })),
      };
    });
  }

  private parseSucursal(
    raw: string | undefined,
    branches: BranchRef[],
  ): number | null {
    if (raw === undefined) return null;

    // 숫자 문자열만 받는다 — 'abc'·'12.5'·'-1' 전부 이 정규식에서 걸린다.
    if (!/^\d+$/.test(raw)) {
      throw new BadRequestException('Sucursal inválida');
    }

    const id = Number(raw);
    const exists = branches.some((b) => b.id === id);

    if (!exists) {
      // 존재 여부를 드러내지 않는다 — 다른 매장 지점 id 도 같은 문구.
      throw new BadRequestException('Sucursal inválida');
    }

    return id;
  }
}
import { Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Sequelize } from 'sequelize';

import {
  ACCOUNTING_SALE_STATUSES,
  saleBranchSql,
} from '../../../reports/sale-status.constants';
import {
  PagosRow,
  WatchSource,
  WatchStoreContext,
} from '../watch-resumen.contract';
import { medioDePagoWatch, MedioDePagoWatch } from './medio-de-pago';
import { VENTAS_BASE_WHERE, VENTAS_DIA_SQL } from './ventas.source';

// =============================================================================
// [Phase 98-08, D-12 ①·D-15 ①] `pagos` 원천 — ② Medios de pago(다섯 칸)을
// `sale_payment_methods` + `credit_ledger` 지점별 **한 문장**(UNION ALL)으로 계산한다.
// =============================================================================
// "오늘 판매"의 정의는 `ventas.source.ts` 가 export 하는 `VENTAS_BASE_WHERE`/
// `VENTAS_DIA_SQL` 을 그대로 쓴다 — 두 원천이 각자 정의하면 Favor/Crédito 재배분이
// ventas 가 보는 판매 집합과 다른 집합을 보게 된다(T-98-61).
//
// ★★ D-15 ① Favor 범위: Favor 칸 = 명시 favor 결제행(위 pagos CTE가 그대로 잡음)
//   + **오늘 판매에 자동 상계된 favor**(`credit_ledger.favor_apply`,
//   `parent_ledger_id IS NOT NULL AND payment_id IS NULL` — sales-create.service.ts
//   4285-4337행의 "외상 판매 시 favor 로 자동 상계" 짝. parent 가 없는 것은 명시 favor
//   결제의 짝(이미 결제행으로 세었다), payment_id 가 있는 것은 **나중의** 회수다).
//   그 자동 상계액만큼 Crédito 칸에서 뺀다 — 결제행(credito)에는 이미 전액이 찍혀
//   있으므로(판매 시점의 sale_credit 은 상계 전 금액), 칸 사이 **이동**일 뿐이라
//   다섯 칸의 합은 바뀌지 않는다.
//
// ★ 취소(Anulación) 역분개 행은 원본의 favor_apply 를 **음수로** 센다(원장은
//   append-only 라 취소돼도 지워지지 않는다) — 결제행 역분개가 음수인 것과 같은
//   부호 규칙. 매칭은 `b.status = 'Anulación'` 이면 `b.nullified_sale_id`,
//   아니면 `b.id` 로 한다.
// =============================================================================

interface PagosQueryRow {
  branch_id: number | null;
  kind: 'pago' | 'favor_auto';
  slug: string | null;
  amount: string | null;
}

@Injectable()
export class PagosSource implements WatchSource<'pagos', PagosRow> {
  readonly key = 'pagos' as const;
  readonly periodo = 'hoy' as const;
  readonly ttlMs = 30_000;

  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  async load(ctx: WatchStoreContext): Promise<PagosRow[]> {
    const sql = `
      WITH base AS (
        SELECT s.id,
               s.status,
               s.nullified_sale_id,
               ${saleBranchSql('s')} AS branch_id
          FROM sales s
         WHERE ${VENTAS_BASE_WHERE}
           AND ${VENTAS_DIA_SQL} = :hoy
      ),
      pagos AS (
        SELECT b.branch_id,
               'pago'::text AS kind,
               pm.slug::text AS slug,
               SUM(spm.amount) AS amount
          FROM base b
          JOIN sale_payment_methods spm ON spm.sale_id = b.id
          LEFT JOIN payment_methods pm ON pm.id = spm.payment_method_id
         GROUP BY b.branch_id, pm.slug
      ),
      favor_auto AS (
        SELECT b.branch_id,
               'favor_auto'::text AS kind,
               NULL::text AS slug,
               SUM(
                 CASE WHEN b.status = 'Anulación' THEN -cl.amount ELSE cl.amount END
               ) AS amount
          FROM base b
          JOIN credit_ledger cl
            ON cl.store_id = :storeId
           AND cl.movement_type = 'favor_apply'
           AND cl.parent_ledger_id IS NOT NULL
           AND cl.payment_id IS NULL
           AND cl.sale_id = CASE
                               WHEN b.status = 'Anulación' THEN b.nullified_sale_id
                               ELSE b.id
                             END
         GROUP BY b.branch_id
      )
      SELECT branch_id, kind, slug, amount FROM pagos
      UNION ALL
      SELECT branch_id, kind, slug, amount FROM favor_auto
    `;

    const rows = await this.sequelize.query<PagosQueryRow>(sql, {
      replacements: {
        storeId: ctx.storeId,
        tz: ctx.tz,
        hoy: ctx.clock.hoy,
        ayer: ctx.clock.ayer,
        accounting: ACCOUNTING_SALE_STATUSES,
      },
      type: QueryTypes.SELECT,
    });

    const byBranch = new Map<number | null, PagosRow>();
    const bucketRow = (branchId: number | null): PagosRow => {
      let row = byBranch.get(branchId);
      if (!row) {
        row = {
          branchId,
          efectivo: 0,
          bancarias: 0,
          credito: 0,
          favor: 0,
          otros: 0,
        };
        byBranch.set(branchId, row);
      }

      return row;
    };

    for (const r of rows) {
      const branchId = r.branch_id === null ? null : Number(r.branch_id);
      const amount = Number(r.amount ?? 0);
      const row = bucketRow(branchId);

      if (r.kind === 'pago') {
        const bucket: MedioDePagoWatch = medioDePagoWatch(r.slug);
        row[bucket] += amount;
      } else {
        // favor_auto — 재배분이다, 새 돈이 아니다: 칸 사이에서 credito → favor 로
        // 옮긴다(다섯 칸의 합은 변하지 않는다, 음수면 반대 방향).
        row.favor += amount;
        row.credito -= amount;
      }
    }

    return [...byBranch.values()];
  }
}
import { Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Sequelize } from 'sequelize';

import {
  ingresoLedgerNoteSql,
  STOCK_TYPE,
} from '../../../stocks/stocks.constants';
import {
  IngresosRow,
  WatchSource,
  WatchStoreContext,
} from '../watch-resumen.contract';

// =============================================================================
// [Phase 98-09, D-12 ③·D-15 ④·⑤] `ingresos` 원천 — ④ Ingresos 의 매입 + 공방
// 수령만 `stocks` 원장 **한 문장**으로 계산한다.
// =============================================================================
// Ventago 에는 매입 전표 테이블이 없다 — **매입 = 수동 재고 입고**(`type IS NULL`,
// `source = 'legacy_opening'` 제외 — 그건 레거시 이관 기초재고라 매입이 아니다) +
// 시스템이 쓴 입고 취소·정정(`type='adjust'`, `ingresoLedgerNoteSql` — stocks.constants.ts
// 의 단일 출처, `v_product_branch_daily_ingreso` 의 net 과 같은 정의).
//
// 제외: 사람 보정(`adjust`, source `manual_adjust`) · 지점 간 이동(`transfer`) ·
// 판매/취소 역분개(`sale`) · 보류(`suspend`) · 반품(`devolucion`) · 폐기(`writeoff`) ·
// 자체 생산(work-order.service.ts 의 `consumo OT#`/`ingreso OT#` — MES 생산, 공방 아님).
//
// 공방 수령 경로는 셋(recepcion.service.ts 최종 공정 수령·lote.service.ts 수동 보정·
// recepcion.service.ts 수령 취소 — memory: talleres-recepciones-has-three-writers)이지만
// **원장 쓰기는 ingresarStockPorProductos/ingresarStockPorMatrix 하나**
// (productStock.service.ts 의 writeStockRows, memory: prod-stock-entry-is-reception-driven)
// 라 note 접두어 하나로 셋을 전부 잡을 수 있다.
//
// ★ 입고 건수(eventos) = D-15 ④ 그날 입고된 **모델(코드 마드레) 수**
//   (`COALESCE(p.parent_id, p.id)` — reportsIngresoCockpit.service.ts 의 product_count
//   와 같은 정의).
// =============================================================================

/**
 * 공방 수령 note 접두어 — 쓰는 쪽(recepcion.service.ts·lote.service.ts) 문구의
 * **단일 출처**. 세 곳이 같은 문자열을 공유하므로 쓰는 쪽 문구가 바뀌면
 * `taller-notes.spec.ts` 가 죽어 워치 집계가 조용히 0 이 되는 사고를 막는다.
 */
export const TALLER_NOTE_PREFIXES = [
  'Recepción lote ',
  'Ingreso manual (corrección) lote ',
  'Reversa ingreso recepción ',
] as const;

/** `note LIKE '접두어%'` 를 OR 로 묶는다 — stocks.constants.ts 의 noteLikeAnySql 과 같은 방식. */
const noteLikeAnySql = (alias: string, prefixes: readonly string[]): string =>
  `(${alias}.note IS NOT NULL AND (${prefixes
    .map((p) => `${alias}.note LIKE '${p.replace(/'/g, "''")}%'`)
    .join(' OR ')}))`;

/** 매입 — 수동 재고 입고(레거시 이관 제외) + 시스템 입고 정정/취소. */
const COMPRA_SQL = `((s.type IS NULL AND COALESCE(s.source, '') <> 'legacy_opening') OR (s.type = '${STOCK_TYPE.ADJUST}' AND ${ingresoLedgerNoteSql('s')}))`;

/** 공방 수령 — production 행 중 쓰는 쪽 note 접두어에 해당하는 것만(자체 생산 OT 제외). */
const TALLER_SQL = `(s.type = '${STOCK_TYPE.PRODUCTION}' AND ${noteLikeAnySql('s', TALLER_NOTE_PREFIXES)})`;

interface IngresosQueryRow {
  branch_id: number | null;
  compras_prendas: string | null;
  compras_eventos: string | null;
  talleres_prendas: string | null;
  talleres_eventos: string | null;
}

@Injectable()
export class IngresosSource implements WatchSource<'ingresos', IngresosRow> {
  readonly key = 'ingresos' as const;
  readonly periodo = 'hoy' as const;
  readonly ttlMs = 30_000;

  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  async load(ctx: WatchStoreContext): Promise<IngresosRow[]> {
    const sql = `
      SELECT s.branch_id AS branch_id,
             SUM(s.stock) FILTER (WHERE ${COMPRA_SQL}) AS compras_prendas,
             COUNT(DISTINCT COALESCE(p.parent_id, p.id))
               FILTER (WHERE ${COMPRA_SQL} AND s.stock > 0) AS compras_eventos,
             SUM(s.stock) FILTER (WHERE ${TALLER_SQL}) AS talleres_prendas,
             COUNT(DISTINCT COALESCE(p.parent_id, p.id))
               FILTER (WHERE ${TALLER_SQL} AND s.stock > 0) AS talleres_eventos
        FROM stocks s
        JOIN "ProductBranch" pb ON pb.id = s.product_branch_id
        JOIN products p ON p.id = pb.product_id AND p.store_id = :storeId
       WHERE s.store_id = :storeId
         AND s.operation_date = :hoy
         AND (${COMPRA_SQL} OR ${TALLER_SQL})
       GROUP BY s.branch_id
    `;

    const rows = await this.sequelize.query<IngresosQueryRow>(sql, {
      replacements: { storeId: ctx.storeId, hoy: ctx.clock.hoy },
      type: QueryTypes.SELECT,
    });

    return rows.map((r) => ({
      branchId: r.branch_id === null ? null : Number(r.branch_id),
      comprasPrendas: Number(r.compras_prendas ?? 0),
      comprasEventos: Number(r.compras_eventos ?? 0),
      talleresPrendas: Number(r.talleres_prendas ?? 0),
      talleresEventos: Number(r.talleres_eventos ?? 0),
    }));
  }
}

codex
현재 코드만 기준으로 교차 정합성을 확인했습니다. 이제 정확한 위치를 붙이기 위해 같은 4개 파일의 행 번호만 확인하겠습니다.
exec
/bin/zsh -lc 'nl -ba src/app/watch/watch-token.guard.ts; nl -ba src/app/watch/resumen/watch-resumen.service.ts; nl -ba src/app/watch/resumen/sources/pagos.source.ts; nl -ba src/app/watch/resumen/sources/ingresos.source.ts' in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
 succeeded in 0ms:
     1	import {
     2	  CanActivate,
     3	  ExecutionContext,
     4	  ForbiddenException,
     5	  Injectable,
     6	  Logger,
     7	  UnauthorizedException,
     8	} from '@nestjs/common';
     9	import { InjectModel } from '@nestjs/sequelize';
    10	import { WatchDevice } from './watch-device.model';
    11	import { hashWatchSecret, isWatchDeviceUsable } from './watch-token.util';
    12	import { loadUserWithStoreRoles } from '../auth/store-filtered-roles';
    13	import { TenantContext } from 'src/common/tenant/tenant-context';
    14	
    15	// =============================================================================
    16	// [Phase 98-02, D-05, T-98-10~T-98-15] 워치 토큰 가드
    17	// =============================================================================
    18	// Passport 기반 가드 클래스를 상속하지 않는다 — 전역 JwtGlobalGuard 가 채운 request.user 를
    19	// 뒤 가드가 지우는 사고를 재발시키지 않기 위해서다(memory:
    20	// route-guard-undoes-global-guard-user). 이 가드는 @Public() 라우트에서 자기
    21	// 완결적으로 인증·인가·테넌트 확정을 전부 한다.
    22	//
    23	// 매 요청 재판정(D-05): 토큰이 살아 있어도 그 사용자가 "지금" admin 이 아니거나
    24	// 매장이 바뀌었으면 401 이다. 98-01 CODEX P1 이 지적한 "claim 시점에 admin 이었다"
    25	// 와 "poll 시점에 admin 이다" 사이의 ms 창은 poll 이 이미 닫았지만, 그 뒤 임의의
    26	// 시점에 권한이 회수되는 긴 창은 이 가드의 매 요청 재판정이 닫는다.
    27	//
    28	// 401 메시지는 모든 거절 경우 동일하다 — 어느 조건이 실패했는지 외부에 드러내면
    29	// 그 자체가 추측 정보가 된다(T-98-15). 서버 로그에는 조건을 구분할 수 있는
    30	// deviceId 만 남긴다 — 토큰·해시는 로그에 쓰지 않는다(D-14 ③).
    31	// =============================================================================
    32	
    33	const WATCH_TOKEN_HEADER = 'x-watch-token';
    34	const WATCH_TOKEN_LENGTH = 43;
    35	const UNUSABLE_MSG = 'Reloj no vinculado';
    36	const ACTIVE_STATUSES = new Set(['active', 'trial']);
    37	
    38	// sliding 갱신 — 10분 안의 재요청은 쓰지 않는다(T-98-18, DB 부하 방지).
    39	const SLIDING_REFRESH_THRESHOLD_MS = 10 * 60 * 1000;
    40	const WATCH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90일(sliding)
    41	
    42	export interface WatchGuardUser {
    43	  id: number;
    44	  storeId: number;
    45	  branchId: number | null;
    46	  roles: string[];
    47	}
    48	
    49	/** 이 가드가 읽고/쓰는 request 모양만 — 나머지 필드는 알 필요 없다(unsafe-any 방지). */
    50	interface WatchGuardRequest {
    51	  headers?: Record<string, unknown>;
    52	  user?: WatchGuardUser;
    53	  watchDevice?: WatchDevice;
    54	}
    55	
    56	@Injectable()
    57	export class WatchTokenGuard implements CanActivate {
    58	  private readonly logger = new Logger(WatchTokenGuard.name);
    59	
    60	  constructor(
    61	    @InjectModel(WatchDevice)
    62	    private readonly watchDeviceModel: typeof WatchDevice,
    63	  ) {}
    64	
    65	  async canActivate(context: ExecutionContext): Promise<boolean> {
    66	    const request = context.switchToHttp().getRequest<WatchGuardRequest>();
    67	    // x-watch-token 헤더만 읽는다 — query/body 는 절대 보지 않는다(T-98-14).
    68	    const header = request.headers?.[WATCH_TOKEN_HEADER];
    69	
    70	    if (typeof header !== 'string' || header.length !== WATCH_TOKEN_LENGTH) {
    71	      throw new UnauthorizedException(UNUSABLE_MSG);
    72	    }
    73	
    74	    const tokenHash = hashWatchSecret(header);
    75	    const device = await this.watchDeviceModel.findOne({
    76	      where: { tokenHash },
    77	    });
    78	    const now = new Date();
    79	
    80	    if (!device || !isWatchDeviceUsable(device, now)) {
    81	      this.logger.warn(
    82	        `[WATCH] 토큰 사용 불가 — device=${device?.id ?? 'unknown'}`,
    83	      );
    84	      throw new UnauthorizedException(UNUSABLE_MSG);
    85	    }
    86	
    87	    // D-05 — 매 요청마다 현재 역할·매장을 다시 읽는다. 토큰을 자동 회수하지
    88	    // 않는다(역할이 돌아오면 다시 쓸 수 있어야 하고, "즉시 401" 은 이 재판정으로
    89	    // 이미 충족된다).
    90	    const resolved = await loadUserWithStoreRoles(device.userId);
    91	
    92	    if (
    93	      !resolved ||
    94	      !ACTIVE_STATUSES.has(resolved.user.status) ||
    95	      resolved.user.storeId !== device.storeId ||
    96	      !resolved.roles.includes('admin')
    97	    ) {
    98	      this.logger.warn(
    99	        `[WATCH] 역할·매장 재판정 실패 — device=${device.id} userId=${device.userId}`,
   100	      );
   101	      throw new UnauthorizedException(UNUSABLE_MSG);
   102	    }
   103	
   104	    TenantContext.resolve({
   105	      storeId: device.storeId,
   106	      isSuperAdmin: false,
   107	      userId: resolved.user.id,
   108	    });
   109	
   110	    // fail-closed 사후 확인 — resolve() 는 컨텍스트가 없으면 조용히 무시하므로
   111	    // 예외 없이도 미해석으로 남을 수 있다.
   112	    const ctx = TenantContext.get();
   113	    if (!ctx?.resolved || typeof ctx.storeId !== 'number') {
   114	      this.logger.error(
   115	        `[WATCH] TenantContext 확정 실패 — device=${device.id}`,
   116	      );
   117	      throw new ForbiddenException(UNUSABLE_MSG);
   118	    }
   119	
   120	    const guardUser: WatchGuardUser = {
   121	      id: resolved.user.id,
   122	      storeId: device.storeId,
   123	      branchId: resolved.user.branchId ?? null,
   124	      roles: resolved.roles,
   125	    };
   126	    request.user = guardUser;
   127	    request.watchDevice = device;
   128	
   129	    this.refreshSliding(device, now);
   130	
   131	    return true;
   132	  }
   133	
   134	  /**
   135	   * sliding 만료 갱신 — lastSeenAt 이 없거나 10분 넘게 지났을 때만 쓴다.
   136	   * 실패해도 요청을 막지 않는다(커밋 후 실패가 응답을 바꾸지 않는다는 원칙과
   137	   * 같은 취지 — 이미 가드를 통과한 요청을 갱신 실패로 되돌리지 않는다).
   138	   */
   139	  private refreshSliding(device: WatchDevice, now: Date): void {
   140	    const lastSeen = device.lastSeenAt?.getTime() ?? 0;
   141	    if (now.getTime() - lastSeen <= SLIDING_REFRESH_THRESHOLD_MS) return;
   142	
   143	    device
   144	      .update({
   145	        lastSeenAt: now,
   146	        expiresAt: new Date(now.getTime() + WATCH_TOKEN_TTL_MS),
   147	      })
   148	      .catch((err: Error) => {
   149	        this.logger.error(
   150	          `[WATCH] sliding 갱신 실패 — device=${device.id}: ${err.message}`,
   151	        );
   152	      });
   153	  }
   154	}
     1	import {
     2	  BadRequestException,
     3	  Inject,
     4	  Injectable,
     5	  Logger,
     6	} from '@nestjs/common';
     7	import { InjectConnection } from '@nestjs/sequelize';
     8	import { QueryTypes, Sequelize } from 'sequelize';
     9	import { MemoryCacheService } from 'src/common/cache/memory-cache.service';
    10	import { storeKey } from 'src/common/cache/cache-key';
    11	import { DEFAULT_STORE_TZ } from 'src/common/constants/timezone';
    12	import { buildSecciones, BranchRef } from './build-secciones';
    13	import { storeClock } from './watch-clock.util';
    14	import {
    15	  SECTION_KEYS,
    16	  SOURCE_KEYS,
    17	  SourceCacheEntry,
    18	  SourceKey,
    19	  WATCH_RESUMEN_SCHEMA_VERSION,
    20	  WATCH_SOURCES,
    21	  WatchResumenV2,
    22	  WatchSource,
    23	  WatchStoreContext,
    24	} from './watch-resumen.contract';
    25	
    26	// =============================================================================
    27	// [Phase 98-02, D-08·D-09] GET /watch/resumen 합성기.
    28	// =============================================================================
    29	// 인증·인가·테넌트 확정은 워치 토큰 가드가 끝낸다 — 이 서비스는 그 뒤에서
    30	// storeId 로만 움직인다(모델 쿼리 금지 — @Public 라우트는 테넌트 훅이 no-op 이므로
    31	// raw SQL + :storeId 바인드만 쓴다, T-98-10).
    32	//
    33	// 캐시는 인가 **뒤**에만 있고 키에 사용자를 넣지 않는다 — admin 은 매장 전체를
    34	// 보므로 매장 단위 결과가 사용자와 무관하게 같다.
    35	//
    36	// [98-10] D-15 ⑤ 지점 활성/비활성 구분 — `loadStoreContext()` 가 `branches.is_active`
    37	// 를 읽어 `BranchRef.isActive` 로 넘긴다. 선택기(sucursales) 노출 판단은
    38	// build-secciones.ts 가 한다(비활성 + 그날 ventas 행 없음 → 숨김). 이 서비스는
    39	// 지점 목록을 활성 여부로 **필터하지 않는다** — `parseSucursal`(아래)과 모든 섹션의
    40	// 원천 데이터(porSucursal·총계)는 활성 여부와 무관하게 전체 지점을 본다. 비활성
    41	// 지점에 오늘 판매가 있으면 돈이 사라지면 안 되므로(narrowing-filter-must-never-widen
    42	// 과 같은 원칙), 걸러내는 지점은 "선택기에 보이는가" 뿐이다.
    43	// =============================================================================
    44	
    45	const FINAL_CACHE_TTL_MS = 30_000;
    46	const CTX_CACHE_TTL_MS = 60_000;
    47	
    48	interface StoreContextRow {
    49	  tienda: string;
    50	  timezone: string | null;
    51	}
    52	
    53	interface BranchContextRow {
    54	  id: number;
    55	  name: string;
    56	  is_active: boolean | null;
    57	}
    58	
    59	interface StoreContext {
    60	  tienda: string;
    61	  timezone: string;
    62	  branches: BranchRef[];
    63	}
    64	
    65	@Injectable()
    66	export class WatchResumenService {
    67	  private readonly logger = new Logger(WatchResumenService.name);
    68	  private readonly sourceByKey: Map<SourceKey, WatchSource>;
    69	
    70	  constructor(
    71	    @InjectConnection() private readonly sequelize: Sequelize,
    72	    private readonly cache: MemoryCacheService,
    73	    @Inject(WATCH_SOURCES) sources: WatchSource[],
    74	  ) {
    75	    const providedKeys = new Set(sources.map((s) => s.key));
    76	    const missing = SOURCE_KEYS.filter((k) => !providedKeys.has(k));
    77	
    78	    if (missing.length > 0) {
    79	      // 부팅 실패 — 원천이 하나라도 빠진 채 배선되면 섹션이 조용히 비는 대신
    80	      // 서버가 안 뜬다(98-10 이 6개를 전부 넘긴다).
    81	      throw new Error(
    82	        `WatchResumenService: WATCH_SOURCES 에 누락된 원천 — ${missing.join(', ')}`,
    83	      );
    84	    }
    85	
    86	    this.sourceByKey = new Map(sources.map((s) => [s.key, s]));
    87	  }
    88	
    89	  async getResumen(
    90	    user: {
    91	      id: number;
    92	      storeId: number;
    93	      branchId: number | null;
    94	      roles: string[];
    95	    },
    96	    rawSucursal: string | undefined,
    97	    opts?: { now?: Date },
    98	  ): Promise<WatchResumenV2> {
    99	    const storeCtx = await this.loadStoreContext(user.storeId);
   100	    const sucursalId = this.parseSucursal(rawSucursal, storeCtx.branches);
   101	
   102	    const now = opts?.now ?? new Date();
   103	    const clock = storeClock(now, storeCtx.timezone);
   104	    const ctx: WatchStoreContext = {
   105	      storeId: user.storeId,
   106	      tz: clock.tzUsada,
   107	      clock,
   108	      user: { id: user.id, branchId: user.branchId, roles: user.roles },
   109	    };
   110	
   111	    const finalKey = storeKey(
   112	      'watch:resumen',
   113	      user.storeId,
   114	      'v2',
   115	      ctx.tz,
   116	      String(sucursalId ?? 'all'),
   117	      clock.hoy,
   118	    );
   119	
   120	    return this.cache.getOrLoad(
   121	      finalKey,
   122	      FINAL_CACHE_TTL_MS,
   123	      () => this.assemble(ctx, storeCtx, sucursalId),
   124	      {
   125	        shouldCache: (value: WatchResumenV2) =>
   126	          SECTION_KEYS.every((k) => value.secciones[k].status === 'ok'),
   127	      },
   128	    );
   129	  }
   130	
   131	  private async assemble(
   132	    ctx: WatchStoreContext,
   133	    storeCtx: StoreContext,
   134	    sucursalId: number | null,
   135	  ): Promise<WatchResumenV2> {
   136	    const rows: Partial<Record<SourceKey, unknown[]>> = {};
   137	    const failed = new Set<SourceKey>();
   138	    const asOf: Record<SourceKey, string | null> = {
   139	      ventas: null,
   140	      pagos: null,
   141	      gastos: null,
   142	      ingresos: null,
   143	      facturacion: null,
   144	      cajas: null,
   145	    };
   146	
   147	    const results = await Promise.allSettled(
   148	      SOURCE_KEYS.map((key) => this.loadSource(key, ctx)),
   149	    );
   150	
   151	    SOURCE_KEYS.forEach((key, i) => {
   152	      const result = results[i];
   153	      if (result.status === 'fulfilled') {
   154	        rows[key] = result.value.rows;
   155	        asOf[key] = result.value.asOf;
   156	      } else {
   157	        failed.add(key);
   158	        this.logger.warn(
   159	          `[WATCH] 원천 실패 — key=${key} storeId=${ctx.storeId}: ${
   160	            (result.reason as Error)?.message ?? result.reason
   161	          }`,
   162	        );
   163	      }
   164	    });
   165	
   166	    const built = buildSecciones({
   167	      rows,
   168	      failed,
   169	      asOf,
   170	      ctx,
   171	      branches: storeCtx.branches,
   172	      sucursalId,
   173	    });
   174	
   175	    return {
   176	      schemaVersion: WATCH_RESUMEN_SCHEMA_VERSION,
   177	      tienda: storeCtx.tienda,
   178	      zona: ctx.tz,
   179	      hoy: ctx.clock.hoy,
   180	      generadoEn: new Date().toISOString(),
   181	      ...built,
   182	    };
   183	  }
   184	
   185	  private async loadSource(
   186	    key: SourceKey,
   187	    ctx: WatchStoreContext,
   188	  ): Promise<SourceCacheEntry<unknown>> {
   189	    // 생성자에서 전부 등록돼 있음을 이미 확인했다(부팅 검사) — 여기서는 단언만.
   190	    const source = this.sourceByKey.get(key) as WatchSource;
   191	    const periodoKey = source.periodo === 'mes' ? ctx.clock.mes : ctx.clock.hoy;
   192	    const cacheKey = storeKey(
   193	      'watch:resumen',
   194	      ctx.storeId,
   195	      'v2',
   196	      ctx.tz,
   197	      'all',
   198	      key,
   199	      periodoKey,
   200	    );
   201	
   202	    return this.cache.getOrLoad(cacheKey, source.ttlMs, async () => ({
   203	      rows: await source.load(ctx),
   204	      asOf: new Date().toISOString(),
   205	    }));
   206	  }
   207	
   208	  private async loadStoreContext(storeId: number): Promise<StoreContext> {
   209	    const key = storeKey('watch:ctx', storeId);
   210	
   211	    return this.cache.getOrLoad(key, CTX_CACHE_TTL_MS, async () => {
   212	      const storeRows = await this.sequelize.query<StoreContextRow>(
   213	        `SELECT COALESCE(NULLIF(alias_name, ''), name) AS tienda, timezone
   214	           FROM stores
   215	          WHERE id = :storeId`,
   216	        { replacements: { storeId }, type: QueryTypes.SELECT },
   217	      );
   218	      const branchRows = await this.sequelize.query<BranchContextRow>(
   219	        `SELECT id, name, is_active
   220	           FROM branches
   221	          WHERE store_id = :storeId
   222	          ORDER BY id`,
   223	        { replacements: { storeId }, type: QueryTypes.SELECT },
   224	      );
   225	
   226	      const store = storeRows[0];
   227	
   228	      return {
   229	        tienda: store?.tienda ?? '',
   230	        timezone: store?.timezone ?? DEFAULT_STORE_TZ,
   231	        branches: branchRows.map((b) => ({
   232	          id: b.id,
   233	          nombre: b.name,
   234	          isActive: b.is_active ?? true,
   235	        })),
   236	      };
   237	    });
   238	  }
   239	
   240	  private parseSucursal(
   241	    raw: string | undefined,
   242	    branches: BranchRef[],
   243	  ): number | null {
   244	    if (raw === undefined) return null;
   245	
   246	    // 숫자 문자열만 받는다 — 'abc'·'12.5'·'-1' 전부 이 정규식에서 걸린다.
   247	    if (!/^\d+$/.test(raw)) {
   248	      throw new BadRequestException('Sucursal inválida');
   249	    }
   250	
   251	    const id = Number(raw);
   252	    const exists = branches.some((b) => b.id === id);
   253	
   254	    if (!exists) {
   255	      // 존재 여부를 드러내지 않는다 — 다른 매장 지점 id 도 같은 문구.
   256	      throw new BadRequestException('Sucursal inválida');
   257	    }
   258	
   259	    return id;
   260	  }
   261	}
     1	import { Injectable } from '@nestjs/common';
     2	import { InjectConnection } from '@nestjs/sequelize';
     3	import { QueryTypes, Sequelize } from 'sequelize';
     4	
     5	import {
     6	  ACCOUNTING_SALE_STATUSES,
     7	  saleBranchSql,
     8	} from '../../../reports/sale-status.constants';
     9	import {
    10	  PagosRow,
    11	  WatchSource,
    12	  WatchStoreContext,
    13	} from '../watch-resumen.contract';
    14	import { medioDePagoWatch, MedioDePagoWatch } from './medio-de-pago';
    15	import { VENTAS_BASE_WHERE, VENTAS_DIA_SQL } from './ventas.source';
    16	
    17	// =============================================================================
    18	// [Phase 98-08, D-12 ①·D-15 ①] `pagos` 원천 — ② Medios de pago(다섯 칸)을
    19	// `sale_payment_methods` + `credit_ledger` 지점별 **한 문장**(UNION ALL)으로 계산한다.
    20	// =============================================================================
    21	// "오늘 판매"의 정의는 `ventas.source.ts` 가 export 하는 `VENTAS_BASE_WHERE`/
    22	// `VENTAS_DIA_SQL` 을 그대로 쓴다 — 두 원천이 각자 정의하면 Favor/Crédito 재배분이
    23	// ventas 가 보는 판매 집합과 다른 집합을 보게 된다(T-98-61).
    24	//
    25	// ★★ D-15 ① Favor 범위: Favor 칸 = 명시 favor 결제행(위 pagos CTE가 그대로 잡음)
    26	//   + **오늘 판매에 자동 상계된 favor**(`credit_ledger.favor_apply`,
    27	//   `parent_ledger_id IS NOT NULL AND payment_id IS NULL` — sales-create.service.ts
    28	//   4285-4337행의 "외상 판매 시 favor 로 자동 상계" 짝. parent 가 없는 것은 명시 favor
    29	//   결제의 짝(이미 결제행으로 세었다), payment_id 가 있는 것은 **나중의** 회수다).
    30	//   그 자동 상계액만큼 Crédito 칸에서 뺀다 — 결제행(credito)에는 이미 전액이 찍혀
    31	//   있으므로(판매 시점의 sale_credit 은 상계 전 금액), 칸 사이 **이동**일 뿐이라
    32	//   다섯 칸의 합은 바뀌지 않는다.
    33	//
    34	// ★ 취소(Anulación) 역분개 행은 원본의 favor_apply 를 **음수로** 센다(원장은
    35	//   append-only 라 취소돼도 지워지지 않는다) — 결제행 역분개가 음수인 것과 같은
    36	//   부호 규칙. 매칭은 `b.status = 'Anulación'` 이면 `b.nullified_sale_id`,
    37	//   아니면 `b.id` 로 한다.
    38	// =============================================================================
    39	
    40	interface PagosQueryRow {
    41	  branch_id: number | null;
    42	  kind: 'pago' | 'favor_auto';
    43	  slug: string | null;
    44	  amount: string | null;
    45	}
    46	
    47	@Injectable()
    48	export class PagosSource implements WatchSource<'pagos', PagosRow> {
    49	  readonly key = 'pagos' as const;
    50	  readonly periodo = 'hoy' as const;
    51	  readonly ttlMs = 30_000;
    52	
    53	  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}
    54	
    55	  async load(ctx: WatchStoreContext): Promise<PagosRow[]> {
    56	    const sql = `
    57	      WITH base AS (
    58	        SELECT s.id,
    59	               s.status,
    60	               s.nullified_sale_id,
    61	               ${saleBranchSql('s')} AS branch_id
    62	          FROM sales s
    63	         WHERE ${VENTAS_BASE_WHERE}
    64	           AND ${VENTAS_DIA_SQL} = :hoy
    65	      ),
    66	      pagos AS (
    67	        SELECT b.branch_id,
    68	               'pago'::text AS kind,
    69	               pm.slug::text AS slug,
    70	               SUM(spm.amount) AS amount
    71	          FROM base b
    72	          JOIN sale_payment_methods spm ON spm.sale_id = b.id
    73	          LEFT JOIN payment_methods pm ON pm.id = spm.payment_method_id
    74	         GROUP BY b.branch_id, pm.slug
    75	      ),
    76	      favor_auto AS (
    77	        SELECT b.branch_id,
    78	               'favor_auto'::text AS kind,
    79	               NULL::text AS slug,
    80	               SUM(
    81	                 CASE WHEN b.status = 'Anulación' THEN -cl.amount ELSE cl.amount END
    82	               ) AS amount
    83	          FROM base b
    84	          JOIN credit_ledger cl
    85	            ON cl.store_id = :storeId
    86	           AND cl.movement_type = 'favor_apply'
    87	           AND cl.parent_ledger_id IS NOT NULL
    88	           AND cl.payment_id IS NULL
    89	           AND cl.sale_id = CASE
    90	                               WHEN b.status = 'Anulación' THEN b.nullified_sale_id
    91	                               ELSE b.id
    92	                             END
    93	         GROUP BY b.branch_id
    94	      )
    95	      SELECT branch_id, kind, slug, amount FROM pagos
    96	      UNION ALL
    97	      SELECT branch_id, kind, slug, amount FROM favor_auto
    98	    `;
    99	
   100	    const rows = await this.sequelize.query<PagosQueryRow>(sql, {
   101	      replacements: {
   102	        storeId: ctx.storeId,
   103	        tz: ctx.tz,
   104	        hoy: ctx.clock.hoy,
   105	        ayer: ctx.clock.ayer,
   106	        accounting: ACCOUNTING_SALE_STATUSES,
   107	      },
   108	      type: QueryTypes.SELECT,
   109	    });
   110	
   111	    const byBranch = new Map<number | null, PagosRow>();
   112	    const bucketRow = (branchId: number | null): PagosRow => {
   113	      let row = byBranch.get(branchId);
   114	      if (!row) {
   115	        row = {
   116	          branchId,
   117	          efectivo: 0,
   118	          bancarias: 0,
   119	          credito: 0,
   120	          favor: 0,
   121	          otros: 0,
   122	        };
   123	        byBranch.set(branchId, row);
   124	      }
   125	
   126	      return row;
   127	    };
   128	
   129	    for (const r of rows) {
   130	      const branchId = r.branch_id === null ? null : Number(r.branch_id);
   131	      const amount = Number(r.amount ?? 0);
   132	      const row = bucketRow(branchId);
   133	
   134	      if (r.kind === 'pago') {
   135	        const bucket: MedioDePagoWatch = medioDePagoWatch(r.slug);
   136	        row[bucket] += amount;
   137	      } else {
   138	        // favor_auto — 재배분이다, 새 돈이 아니다: 칸 사이에서 credito → favor 로
   139	        // 옮긴다(다섯 칸의 합은 변하지 않는다, 음수면 반대 방향).
   140	        row.favor += amount;
   141	        row.credito -= amount;
   142	      }
   143	    }
   144	
   145	    return [...byBranch.values()];
   146	  }
   147	}
     1	import { Injectable } from '@nestjs/common';
     2	import { InjectConnection } from '@nestjs/sequelize';
     3	import { QueryTypes, Sequelize } from 'sequelize';
     4	
     5	import {
     6	  ingresoLedgerNoteSql,
     7	  STOCK_TYPE,
     8	} from '../../../stocks/stocks.constants';
     9	import {
    10	  IngresosRow,
    11	  WatchSource,
    12	  WatchStoreContext,
    13	} from '../watch-resumen.contract';
    14	
    15	// =============================================================================
    16	// [Phase 98-09, D-12 ③·D-15 ④·⑤] `ingresos` 원천 — ④ Ingresos 의 매입 + 공방
    17	// 수령만 `stocks` 원장 **한 문장**으로 계산한다.
    18	// =============================================================================
    19	// Ventago 에는 매입 전표 테이블이 없다 — **매입 = 수동 재고 입고**(`type IS NULL`,
    20	// `source = 'legacy_opening'` 제외 — 그건 레거시 이관 기초재고라 매입이 아니다) +
    21	// 시스템이 쓴 입고 취소·정정(`type='adjust'`, `ingresoLedgerNoteSql` — stocks.constants.ts
    22	// 의 단일 출처, `v_product_branch_daily_ingreso` 의 net 과 같은 정의).
    23	//
    24	// 제외: 사람 보정(`adjust`, source `manual_adjust`) · 지점 간 이동(`transfer`) ·
    25	// 판매/취소 역분개(`sale`) · 보류(`suspend`) · 반품(`devolucion`) · 폐기(`writeoff`) ·
    26	// 자체 생산(work-order.service.ts 의 `consumo OT#`/`ingreso OT#` — MES 생산, 공방 아님).
    27	//
    28	// 공방 수령 경로는 셋(recepcion.service.ts 최종 공정 수령·lote.service.ts 수동 보정·
    29	// recepcion.service.ts 수령 취소 — memory: talleres-recepciones-has-three-writers)이지만
    30	// **원장 쓰기는 ingresarStockPorProductos/ingresarStockPorMatrix 하나**
    31	// (productStock.service.ts 의 writeStockRows, memory: prod-stock-entry-is-reception-driven)
    32	// 라 note 접두어 하나로 셋을 전부 잡을 수 있다.
    33	//
    34	// ★ 입고 건수(eventos) = D-15 ④ 그날 입고된 **모델(코드 마드레) 수**
    35	//   (`COALESCE(p.parent_id, p.id)` — reportsIngresoCockpit.service.ts 의 product_count
    36	//   와 같은 정의).
    37	// =============================================================================
    38	
    39	/**
    40	 * 공방 수령 note 접두어 — 쓰는 쪽(recepcion.service.ts·lote.service.ts) 문구의
    41	 * **단일 출처**. 세 곳이 같은 문자열을 공유하므로 쓰는 쪽 문구가 바뀌면
    42	 * `taller-notes.spec.ts` 가 죽어 워치 집계가 조용히 0 이 되는 사고를 막는다.
    43	 */
    44	export const TALLER_NOTE_PREFIXES = [
    45	  'Recepción lote ',
    46	  'Ingreso manual (corrección) lote ',
    47	  'Reversa ingreso recepción ',
    48	] as const;
    49	
    50	/** `note LIKE '접두어%'` 를 OR 로 묶는다 — stocks.constants.ts 의 noteLikeAnySql 과 같은 방식. */
    51	const noteLikeAnySql = (alias: string, prefixes: readonly string[]): string =>
    52	  `(${alias}.note IS NOT NULL AND (${prefixes
    53	    .map((p) => `${alias}.note LIKE '${p.replace(/'/g, "''")}%'`)
    54	    .join(' OR ')}))`;
    55	
    56	/** 매입 — 수동 재고 입고(레거시 이관 제외) + 시스템 입고 정정/취소. */
    57	const COMPRA_SQL = `((s.type IS NULL AND COALESCE(s.source, '') <> 'legacy_opening') OR (s.type = '${STOCK_TYPE.ADJUST}' AND ${ingresoLedgerNoteSql('s')}))`;
    58	
    59	/** 공방 수령 — production 행 중 쓰는 쪽 note 접두어에 해당하는 것만(자체 생산 OT 제외). */
    60	const TALLER_SQL = `(s.type = '${STOCK_TYPE.PRODUCTION}' AND ${noteLikeAnySql('s', TALLER_NOTE_PREFIXES)})`;
    61	
    62	interface IngresosQueryRow {
    63	  branch_id: number | null;
    64	  compras_prendas: string | null;
    65	  compras_eventos: string | null;
    66	  talleres_prendas: string | null;
    67	  talleres_eventos: string | null;
    68	}
    69	
    70	@Injectable()
    71	export class IngresosSource implements WatchSource<'ingresos', IngresosRow> {
    72	  readonly key = 'ingresos' as const;
    73	  readonly periodo = 'hoy' as const;
    74	  readonly ttlMs = 30_000;
    75	
    76	  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}
    77	
    78	  async load(ctx: WatchStoreContext): Promise<IngresosRow[]> {
    79	    const sql = `
    80	      SELECT s.branch_id AS branch_id,
    81	             SUM(s.stock) FILTER (WHERE ${COMPRA_SQL}) AS compras_prendas,
    82	             COUNT(DISTINCT COALESCE(p.parent_id, p.id))
    83	               FILTER (WHERE ${COMPRA_SQL} AND s.stock > 0) AS compras_eventos,
    84	             SUM(s.stock) FILTER (WHERE ${TALLER_SQL}) AS talleres_prendas,
    85	             COUNT(DISTINCT COALESCE(p.parent_id, p.id))
    86	               FILTER (WHERE ${TALLER_SQL} AND s.stock > 0) AS talleres_eventos
    87	        FROM stocks s
    88	        JOIN "ProductBranch" pb ON pb.id = s.product_branch_id
    89	        JOIN products p ON p.id = pb.product_id AND p.store_id = :storeId
    90	       WHERE s.store_id = :storeId
    91	         AND s.operation_date = :hoy
    92	         AND (${COMPRA_SQL} OR ${TALLER_SQL})
    93	       GROUP BY s.branch_id
    94	    `;
    95	
    96	    const rows = await this.sequelize.query<IngresosQueryRow>(sql, {
    97	      replacements: { storeId: ctx.storeId, hoy: ctx.clock.hoy },
    98	      type: QueryTypes.SELECT,
    99	    });
   100	
   101	    return rows.map((r) => ({
   102	      branchId: r.branch_id === null ? null : Number(r.branch_id),
   103	      comprasPrendas: Number(r.compras_prendas ?? 0),
   104	      comprasEventos: Number(r.compras_eventos ?? 0),
   105	      talleresPrendas: Number(r.talleres_prendas ?? 0),
   106	      talleresEventos: Number(r.talleres_eventos ?? 0),
   107	    }));
   108	  }
   109	}

codex
지정된 4개 파일만 읽었으며 git/diff는 사용하지 않았습니다.

- **P1 — TenantContext 재판정이 실제 매장 일치를 검증하지 않음.**  
  [watch-token.guard.ts:104](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/watch-token.guard.ts:104)에서 `device.storeId`로 `resolve()`한 뒤, [watch-token.guard.ts:112](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/watch-token.guard.ts:112)의 사후 검사는 `resolved === true`와 `storeId`가 숫자인지만 확인합니다. 기존 컨텍스트가 이미 다른 매장으로 확정되어 `resolve()`가 무시되는 경우에도 통과할 수 있습니다. `ctx.storeId === device.storeId`, 가능하면 `ctx.userId === resolved.user.id`까지 검증해야 합니다. 현재 주석의 “fail-closed” 보장이 성립하지 않습니다.

- **P2 — favor 자동상계 재배분이 Crédito 잔액 존재 여부를 확인하지 않아 음수 버킷을 만들 수 있음.**  
  [pagos.source.ts:76](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/pagos.source.ts:76)에서 조건에 맞는 `favor_apply` 전액을 합산한 후, [pagos.source.ts:140](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/pagos.source.ts:140)에서 무조건 `favor += amount`, `credito -= amount` 합니다. 그러나 쿼리는 대응하는 `sale_payment_methods` 행이 실제 Crédito로 분류됐는지 또는 금액이 충분한지 연결·검증하지 않습니다. 누락·정정·부분기록 데이터에서는 `credito < 0`이 되고, “칸 사이 이동”이라는 불변식도 의미상 깨집니다. 판매별 Crédito 금액과 자동상계액을 결합하여 `favor_auto`가 대응 Crédito를 초과하지 않게 해야 합니다.

- **P2 — 당일 입고 후 취소된 모델도 eventos에 남음.**  
  [ingresos.source.ts:81](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:81)는 수량을 순합산하지만, eventos는 [ingresos.source.ts:82](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:82) 및 [ingresos.source.ts:85](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:85)에서 개별 양수 행이 하나라도 있으면 모델을 셉니다. 같은 날 `+N` 입고와 `-N` 취소가 있으면 `prendas=0`, `eventos=1`이 됩니다. 모델별로 먼저 순수량을 집계한 뒤 순수량이 양수인 모델만 세어야 합니다.

- **P2 — “수동 매입만”이라는 제외 규칙이 SQL에 구현되지 않음.**  
  [ingresos.source.ts:57](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:57)의 매입 조건은 사실상 `type IS NULL`인 모든 행을 포함하고 `legacy_opening`만 제외합니다. 주석이 정의한 “수동 재고 입고”를 식별하는 source allowlist가 없어, 다른 시스템·이관 경로가 `type=NULL`로 기록되면 매입으로 섞입니다. 제외 목록 방식보다 허용된 수동입고 source를 명시하는 편이 안전합니다.

- **P3 — store가 사라지거나 조회되지 않아도 빈 매장 컨텍스트로 계속 진행함.**  
  [watch-resumen.service.ts:226](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/watch-resumen.service.ts:226)에서 store 행이 없어도 [watch-resumen.service.ts:228](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/watch-resumen.service.ts:228)처럼 빈 이름과 기본 timezone으로 resumen을 생성합니다. 가드 재판정 이후 삭제·불일치가 생긴 경우 명시적으로 실패시키는 것이 정합성 면에서 맞습니다.

가장 우선적인 수정 대상은 TenantContext의 정확한 매장 일치 검증입니다. 그다음 ingresos의 모델별 순집계와 favor 재배분의 Crédito 대응 검증이 필요합니다.
tokens used
22,123
지정된 4개 파일만 읽었으며 git/diff는 사용하지 않았습니다.

- **P1 — TenantContext 재판정이 실제 매장 일치를 검증하지 않음.**  
  [watch-token.guard.ts:104](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/watch-token.guard.ts:104)에서 `device.storeId`로 `resolve()`한 뒤, [watch-token.guard.ts:112](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/watch-token.guard.ts:112)의 사후 검사는 `resolved === true`와 `storeId`가 숫자인지만 확인합니다. 기존 컨텍스트가 이미 다른 매장으로 확정되어 `resolve()`가 무시되는 경우에도 통과할 수 있습니다. `ctx.storeId === device.storeId`, 가능하면 `ctx.userId === resolved.user.id`까지 검증해야 합니다. 현재 주석의 “fail-closed” 보장이 성립하지 않습니다.

- **P2 — favor 자동상계 재배분이 Crédito 잔액 존재 여부를 확인하지 않아 음수 버킷을 만들 수 있음.**  
  [pagos.source.ts:76](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/pagos.source.ts:76)에서 조건에 맞는 `favor_apply` 전액을 합산한 후, [pagos.source.ts:140](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/pagos.source.ts:140)에서 무조건 `favor += amount`, `credito -= amount` 합니다. 그러나 쿼리는 대응하는 `sale_payment_methods` 행이 실제 Crédito로 분류됐는지 또는 금액이 충분한지 연결·검증하지 않습니다. 누락·정정·부분기록 데이터에서는 `credito < 0`이 되고, “칸 사이 이동”이라는 불변식도 의미상 깨집니다. 판매별 Crédito 금액과 자동상계액을 결합하여 `favor_auto`가 대응 Crédito를 초과하지 않게 해야 합니다.

- **P2 — 당일 입고 후 취소된 모델도 eventos에 남음.**  
  [ingresos.source.ts:81](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:81)는 수량을 순합산하지만, eventos는 [ingresos.source.ts:82](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:82) 및 [ingresos.source.ts:85](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:85)에서 개별 양수 행이 하나라도 있으면 모델을 셉니다. 같은 날 `+N` 입고와 `-N` 취소가 있으면 `prendas=0`, `eventos=1`이 됩니다. 모델별로 먼저 순수량을 집계한 뒤 순수량이 양수인 모델만 세어야 합니다.

- **P2 — “수동 매입만”이라는 제외 규칙이 SQL에 구현되지 않음.**  
  [ingresos.source.ts:57](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/sources/ingresos.source.ts:57)의 매입 조건은 사실상 `type IS NULL`인 모든 행을 포함하고 `legacy_opening`만 제외합니다. 주석이 정의한 “수동 재고 입고”를 식별하는 source allowlist가 없어, 다른 시스템·이관 경로가 `type=NULL`로 기록되면 매입으로 섞입니다. 제외 목록 방식보다 허용된 수동입고 source를 명시하는 편이 안전합니다.

- **P3 — store가 사라지거나 조회되지 않아도 빈 매장 컨텍스트로 계속 진행함.**  
  [watch-resumen.service.ts:226](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/watch-resumen.service.ts:226)에서 store 행이 없어도 [watch-resumen.service.ts:228](/Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/watch/resumen/watch-resumen.service.ts:228)처럼 빈 이름과 기본 timezone으로 resumen을 생성합니다. 가드 재판정 이후 삭제·불일치가 생긴 경우 명시적으로 실패시키는 것이 정합성 면에서 맞습니다.

가장 우선적인 수정 대상은 TenantContext의 정확한 매장 일치 검증입니다. 그다음 ingresos의 모델별 순집계와 favor 재배분의 Crédito 대응 검증이 필요합니다.
```

## Round 2 (after P1/P2 fixes)
```
Reading additional input from stdin...
2026-10-05T00:48:44.247402Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a10988-d448-7a41-9b73-de13a0709077
--------
user
git 명령을 실행하지 마라. diff 를 보지 마라. 아래 4개 파일만 다시 읽어라. 이전에 P1(TenantContext storeId 불일치 미검증)·P2(ingresos eventos 순수량 미반영) 를 지적했는데 고쳤다. 고쳐졌는지와 새 결함이 있는지만 P1/P2/P3 로 답하라. 파일: src/app/watch/watch-token.guard.ts, src/app/watch/resumen/watch-resumen.service.ts, src/app/watch/resumen/sources/pagos.source.ts, src/app/watch/resumen/sources/ingresos.source.ts.
codex
지정한 네 파일만 읽고, git/diff 없이 이전 P1·P2 수정 여부와 새 결함만 확인하겠습니다.
exec
/bin/zsh -lc "sed -n '1,240p' src/app/watch/watch-token.guard.ts; sed -n '1,300p' src/app/watch/resumen/watch-resumen.service.ts; sed -n '1,260p' src/app/watch/resumen/sources/pagos.source.ts; sed -n '1,300p' src/app/watch/resumen/sources/ingresos.source.ts" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago
 succeeded in 0ms:
import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/sequelize';
import { WatchDevice } from './watch-device.model';
import { hashWatchSecret, isWatchDeviceUsable } from './watch-token.util';
import { loadUserWithStoreRoles } from '../auth/store-filtered-roles';
import { TenantContext } from 'src/common/tenant/tenant-context';

// =============================================================================
// [Phase 98-02, D-05, T-98-10~T-98-15] 워치 토큰 가드
// =============================================================================
// Passport 기반 가드 클래스를 상속하지 않는다 — 전역 JwtGlobalGuard 가 채운 request.user 를
// 뒤 가드가 지우는 사고를 재발시키지 않기 위해서다(memory:
// route-guard-undoes-global-guard-user). 이 가드는 @Public() 라우트에서 자기
// 완결적으로 인증·인가·테넌트 확정을 전부 한다.
//
// 매 요청 재판정(D-05): 토큰이 살아 있어도 그 사용자가 "지금" admin 이 아니거나
// 매장이 바뀌었으면 401 이다. 98-01 CODEX P1 이 지적한 "claim 시점에 admin 이었다"
// 와 "poll 시점에 admin 이다" 사이의 ms 창은 poll 이 이미 닫았지만, 그 뒤 임의의
// 시점에 권한이 회수되는 긴 창은 이 가드의 매 요청 재판정이 닫는다.
//
// 401 메시지는 모든 거절 경우 동일하다 — 어느 조건이 실패했는지 외부에 드러내면
// 그 자체가 추측 정보가 된다(T-98-15). 서버 로그에는 조건을 구분할 수 있는
// deviceId 만 남긴다 — 토큰·해시는 로그에 쓰지 않는다(D-14 ③).
// =============================================================================

const WATCH_TOKEN_HEADER = 'x-watch-token';
const WATCH_TOKEN_LENGTH = 43;
const UNUSABLE_MSG = 'Reloj no vinculado';
const ACTIVE_STATUSES = new Set(['active', 'trial']);

// sliding 갱신 — 10분 안의 재요청은 쓰지 않는다(T-98-18, DB 부하 방지).
const SLIDING_REFRESH_THRESHOLD_MS = 10 * 60 * 1000;
const WATCH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90일(sliding)

export interface WatchGuardUser {
  id: number;
  storeId: number;
  branchId: number | null;
  roles: string[];
}

/** 이 가드가 읽고/쓰는 request 모양만 — 나머지 필드는 알 필요 없다(unsafe-any 방지). */
interface WatchGuardRequest {
  headers?: Record<string, unknown>;
  user?: WatchGuardUser;
  watchDevice?: WatchDevice;
}

@Injectable()
export class WatchTokenGuard implements CanActivate {
  private readonly logger = new Logger(WatchTokenGuard.name);

  constructor(
    @InjectModel(WatchDevice)
    private readonly watchDeviceModel: typeof WatchDevice,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<WatchGuardRequest>();
    // x-watch-token 헤더만 읽는다 — query/body 는 절대 보지 않는다(T-98-14).
    const header = request.headers?.[WATCH_TOKEN_HEADER];

    if (typeof header !== 'string' || header.length !== WATCH_TOKEN_LENGTH) {
      throw new UnauthorizedException(UNUSABLE_MSG);
    }

    const tokenHash = hashWatchSecret(header);
    const device = await this.watchDeviceModel.findOne({
      where: { tokenHash },
    });
    const now = new Date();

    if (!device || !isWatchDeviceUsable(device, now)) {
      this.logger.warn(
        `[WATCH] 토큰 사용 불가 — device=${device?.id ?? 'unknown'}`,
      );
      throw new UnauthorizedException(UNUSABLE_MSG);
    }

    // D-05 — 매 요청마다 현재 역할·매장을 다시 읽는다. 토큰을 자동 회수하지
    // 않는다(역할이 돌아오면 다시 쓸 수 있어야 하고, "즉시 401" 은 이 재판정으로
    // 이미 충족된다).
    const resolved = await loadUserWithStoreRoles(device.userId);

    if (
      !resolved ||
      !ACTIVE_STATUSES.has(resolved.user.status) ||
      resolved.user.storeId !== device.storeId ||
      !resolved.roles.includes('admin')
    ) {
      this.logger.warn(
        `[WATCH] 역할·매장 재판정 실패 — device=${device.id} userId=${device.userId}`,
      );
      throw new UnauthorizedException(UNUSABLE_MSG);
    }

    TenantContext.resolve({
      storeId: device.storeId,
      isSuperAdmin: false,
      userId: resolved.user.id,
    });

    // fail-closed 사후 확인 — resolve() 는 컨텍스트가 없으면 조용히 무시하므로
    // 예외 없이도 미해석으로 남을 수 있다.
    //
    // [98-10, CODEX P1 자문 — 검증 결과는 아래] `ctx.storeId === device.storeId`
    // 를 명시로 확인한다. 현재 `TenantContext.resolve()` 구현은 컨텍스트가 있으면
    // storeId 를 **항상 동기적으로 덮어쓴다**(이미 다른 매장으로 확정돼 있어도
    // "무시"하는 분기가 없다 — tenant-context.ts 의 resolve() 전문 확인) — 그래서
    // 이 비교는 현재로서는 항상 참이다(재현 안 됨). 그래도 이 구현이 바뀌어도
    // 조용히 깨지지 않도록 **명시 단언으로 남긴다**(방어적, 비용 0).
    const ctx = TenantContext.get();
    if (
      !ctx?.resolved ||
      typeof ctx.storeId !== 'number' ||
      ctx.storeId !== device.storeId
    ) {
      this.logger.error(
        `[WATCH] TenantContext 확정 실패 — device=${device.id}`,
      );
      throw new ForbiddenException(UNUSABLE_MSG);
    }

    const guardUser: WatchGuardUser = {
      id: resolved.user.id,
      storeId: device.storeId,
      branchId: resolved.user.branchId ?? null,
      roles: resolved.roles,
    };
    request.user = guardUser;
    request.watchDevice = device;

    this.refreshSliding(device, now);

    return true;
  }

  /**
   * sliding 만료 갱신 — lastSeenAt 이 없거나 10분 넘게 지났을 때만 쓴다.
   * 실패해도 요청을 막지 않는다(커밋 후 실패가 응답을 바꾸지 않는다는 원칙과
   * 같은 취지 — 이미 가드를 통과한 요청을 갱신 실패로 되돌리지 않는다).
   */
  private refreshSliding(device: WatchDevice, now: Date): void {
    const lastSeen = device.lastSeenAt?.getTime() ?? 0;
    if (now.getTime() - lastSeen <= SLIDING_REFRESH_THRESHOLD_MS) return;

    device
      .update({
        lastSeenAt: now,
        expiresAt: new Date(now.getTime() + WATCH_TOKEN_TTL_MS),
      })
      .catch((err: Error) => {
        this.logger.error(
          `[WATCH] sliding 갱신 실패 — device=${device.id}: ${err.message}`,
        );
      });
  }
}
import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Sequelize } from 'sequelize';
import { MemoryCacheService } from 'src/common/cache/memory-cache.service';
import { storeKey } from 'src/common/cache/cache-key';
import { DEFAULT_STORE_TZ } from 'src/common/constants/timezone';
import { buildSecciones, BranchRef } from './build-secciones';
import { storeClock } from './watch-clock.util';
import {
  SECTION_KEYS,
  SOURCE_KEYS,
  SourceCacheEntry,
  SourceKey,
  WATCH_RESUMEN_SCHEMA_VERSION,
  WATCH_SOURCES,
  WatchResumenV2,
  WatchSource,
  WatchStoreContext,
} from './watch-resumen.contract';

// =============================================================================
// [Phase 98-02, D-08·D-09] GET /watch/resumen 합성기.
// =============================================================================
// 인증·인가·테넌트 확정은 워치 토큰 가드가 끝낸다 — 이 서비스는 그 뒤에서
// storeId 로만 움직인다(모델 쿼리 금지 — @Public 라우트는 테넌트 훅이 no-op 이므로
// raw SQL + :storeId 바인드만 쓴다, T-98-10).
//
// 캐시는 인가 **뒤**에만 있고 키에 사용자를 넣지 않는다 — admin 은 매장 전체를
// 보므로 매장 단위 결과가 사용자와 무관하게 같다.
//
// [98-10] D-15 ⑤ 지점 활성/비활성 구분 — `loadStoreContext()` 가 `branches.is_active`
// 를 읽어 `BranchRef.isActive` 로 넘긴다. 선택기(sucursales) 노출 판단은
// build-secciones.ts 가 한다(비활성 + 그날 ventas 행 없음 → 숨김). 이 서비스는
// 지점 목록을 활성 여부로 **필터하지 않는다** — `parseSucursal`(아래)과 모든 섹션의
// 원천 데이터(porSucursal·총계)는 활성 여부와 무관하게 전체 지점을 본다. 비활성
// 지점에 오늘 판매가 있으면 돈이 사라지면 안 되므로(narrowing-filter-must-never-widen
// 과 같은 원칙), 걸러내는 지점은 "선택기에 보이는가" 뿐이다.
// =============================================================================

const FINAL_CACHE_TTL_MS = 30_000;
const CTX_CACHE_TTL_MS = 60_000;

interface StoreContextRow {
  tienda: string;
  timezone: string | null;
}

interface BranchContextRow {
  id: number;
  name: string;
  is_active: boolean | null;
}

interface StoreContext {
  tienda: string;
  timezone: string;
  branches: BranchRef[];
}

@Injectable()
export class WatchResumenService {
  private readonly logger = new Logger(WatchResumenService.name);
  private readonly sourceByKey: Map<SourceKey, WatchSource>;

  constructor(
    @InjectConnection() private readonly sequelize: Sequelize,
    private readonly cache: MemoryCacheService,
    @Inject(WATCH_SOURCES) sources: WatchSource[],
  ) {
    const providedKeys = new Set(sources.map((s) => s.key));
    const missing = SOURCE_KEYS.filter((k) => !providedKeys.has(k));

    if (missing.length > 0) {
      // 부팅 실패 — 원천이 하나라도 빠진 채 배선되면 섹션이 조용히 비는 대신
      // 서버가 안 뜬다(98-10 이 6개를 전부 넘긴다).
      throw new Error(
        `WatchResumenService: WATCH_SOURCES 에 누락된 원천 — ${missing.join(', ')}`,
      );
    }

    this.sourceByKey = new Map(sources.map((s) => [s.key, s]));
  }

  async getResumen(
    user: {
      id: number;
      storeId: number;
      branchId: number | null;
      roles: string[];
    },
    rawSucursal: string | undefined,
    opts?: { now?: Date },
  ): Promise<WatchResumenV2> {
    const storeCtx = await this.loadStoreContext(user.storeId);
    const sucursalId = this.parseSucursal(rawSucursal, storeCtx.branches);

    const now = opts?.now ?? new Date();
    const clock = storeClock(now, storeCtx.timezone);
    const ctx: WatchStoreContext = {
      storeId: user.storeId,
      tz: clock.tzUsada,
      clock,
      user: { id: user.id, branchId: user.branchId, roles: user.roles },
    };

    const finalKey = storeKey(
      'watch:resumen',
      user.storeId,
      'v2',
      ctx.tz,
      String(sucursalId ?? 'all'),
      clock.hoy,
    );

    return this.cache.getOrLoad(
      finalKey,
      FINAL_CACHE_TTL_MS,
      () => this.assemble(ctx, storeCtx, sucursalId),
      {
        shouldCache: (value: WatchResumenV2) =>
          SECTION_KEYS.every((k) => value.secciones[k].status === 'ok'),
      },
    );
  }

  private async assemble(
    ctx: WatchStoreContext,
    storeCtx: StoreContext,
    sucursalId: number | null,
  ): Promise<WatchResumenV2> {
    const rows: Partial<Record<SourceKey, unknown[]>> = {};
    const failed = new Set<SourceKey>();
    const asOf: Record<SourceKey, string | null> = {
      ventas: null,
      pagos: null,
      gastos: null,
      ingresos: null,
      facturacion: null,
      cajas: null,
    };

    const results = await Promise.allSettled(
      SOURCE_KEYS.map((key) => this.loadSource(key, ctx)),
    );

    SOURCE_KEYS.forEach((key, i) => {
      const result = results[i];
      if (result.status === 'fulfilled') {
        rows[key] = result.value.rows;
        asOf[key] = result.value.asOf;
      } else {
        failed.add(key);
        this.logger.warn(
          `[WATCH] 원천 실패 — key=${key} storeId=${ctx.storeId}: ${
            (result.reason as Error)?.message ?? result.reason
          }`,
        );
      }
    });

    const built = buildSecciones({
      rows,
      failed,
      asOf,
      ctx,
      branches: storeCtx.branches,
      sucursalId,
    });

    return {
      schemaVersion: WATCH_RESUMEN_SCHEMA_VERSION,
      tienda: storeCtx.tienda,
      zona: ctx.tz,
      hoy: ctx.clock.hoy,
      generadoEn: new Date().toISOString(),
      ...built,
    };
  }

  private async loadSource(
    key: SourceKey,
    ctx: WatchStoreContext,
  ): Promise<SourceCacheEntry<unknown>> {
    // 생성자에서 전부 등록돼 있음을 이미 확인했다(부팅 검사) — 여기서는 단언만.
    const source = this.sourceByKey.get(key) as WatchSource;
    const periodoKey = source.periodo === 'mes' ? ctx.clock.mes : ctx.clock.hoy;
    const cacheKey = storeKey(
      'watch:resumen',
      ctx.storeId,
      'v2',
      ctx.tz,
      'all',
      key,
      periodoKey,
    );

    return this.cache.getOrLoad(cacheKey, source.ttlMs, async () => ({
      rows: await source.load(ctx),
      asOf: new Date().toISOString(),
    }));
  }

  private async loadStoreContext(storeId: number): Promise<StoreContext> {
    const key = storeKey('watch:ctx', storeId);

    return this.cache.getOrLoad(key, CTX_CACHE_TTL_MS, async () => {
      const storeRows = await this.sequelize.query<StoreContextRow>(
        `SELECT COALESCE(NULLIF(alias_name, ''), name) AS tienda, timezone
           FROM stores
          WHERE id = :storeId`,
        { replacements: { storeId }, type: QueryTypes.SELECT },
      );
      const branchRows = await this.sequelize.query<BranchContextRow>(
        `SELECT id, name, is_active
           FROM branches
          WHERE store_id = :storeId
          ORDER BY id`,
        { replacements: { storeId }, type: QueryTypes.SELECT },
      );

      const store = storeRows[0];

      return {
        tienda: store?.tienda ?? '',
        timezone: store?.timezone ?? DEFAULT_STORE_TZ,
        branches: branchRows.map((b) => ({
          id: b.id,
          nombre: b.name,
          isActive: b.is_active ?? true,
        })),
      };
    });
  }

  private parseSucursal(
    raw: string | undefined,
    branches: BranchRef[],
  ): number | null {
    if (raw === undefined) return null;

    // 숫자 문자열만 받는다 — 'abc'·'12.5'·'-1' 전부 이 정규식에서 걸린다.
    if (!/^\d+$/.test(raw)) {
      throw new BadRequestException('Sucursal inválida');
    }

    const id = Number(raw);
    const exists = branches.some((b) => b.id === id);

    if (!exists) {
      // 존재 여부를 드러내지 않는다 — 다른 매장 지점 id 도 같은 문구.
      throw new BadRequestException('Sucursal inválida');
    }

    return id;
  }
}
import { Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Sequelize } from 'sequelize';

import {
  ACCOUNTING_SALE_STATUSES,
  saleBranchSql,
} from '../../../reports/sale-status.constants';
import {
  PagosRow,
  WatchSource,
  WatchStoreContext,
} from '../watch-resumen.contract';
import { medioDePagoWatch, MedioDePagoWatch } from './medio-de-pago';
import { VENTAS_BASE_WHERE, VENTAS_DIA_SQL } from './ventas.source';

// =============================================================================
// [Phase 98-08, D-12 ①·D-15 ①] `pagos` 원천 — ② Medios de pago(다섯 칸)을
// `sale_payment_methods` + `credit_ledger` 지점별 **한 문장**(UNION ALL)으로 계산한다.
// =============================================================================
// "오늘 판매"의 정의는 `ventas.source.ts` 가 export 하는 `VENTAS_BASE_WHERE`/
// `VENTAS_DIA_SQL` 을 그대로 쓴다 — 두 원천이 각자 정의하면 Favor/Crédito 재배분이
// ventas 가 보는 판매 집합과 다른 집합을 보게 된다(T-98-61).
//
// ★★ D-15 ① Favor 범위: Favor 칸 = 명시 favor 결제행(위 pagos CTE가 그대로 잡음)
//   + **오늘 판매에 자동 상계된 favor**(`credit_ledger.favor_apply`,
//   `parent_ledger_id IS NOT NULL AND payment_id IS NULL` — sales-create.service.ts
//   4285-4337행의 "외상 판매 시 favor 로 자동 상계" 짝. parent 가 없는 것은 명시 favor
//   결제의 짝(이미 결제행으로 세었다), payment_id 가 있는 것은 **나중의** 회수다).
//   그 자동 상계액만큼 Crédito 칸에서 뺀다 — 결제행(credito)에는 이미 전액이 찍혀
//   있으므로(판매 시점의 sale_credit 은 상계 전 금액), 칸 사이 **이동**일 뿐이라
//   다섯 칸의 합은 바뀌지 않는다.
//
// ★ 취소(Anulación) 역분개 행은 원본의 favor_apply 를 **음수로** 센다(원장은
//   append-only 라 취소돼도 지워지지 않는다) — 결제행 역분개가 음수인 것과 같은
//   부호 규칙. 매칭은 `b.status = 'Anulación'` 이면 `b.nullified_sale_id`,
//   아니면 `b.id` 로 한다.
// =============================================================================

interface PagosQueryRow {
  branch_id: number | null;
  kind: 'pago' | 'favor_auto';
  slug: string | null;
  amount: string | null;
}

@Injectable()
export class PagosSource implements WatchSource<'pagos', PagosRow> {
  readonly key = 'pagos' as const;
  readonly periodo = 'hoy' as const;
  readonly ttlMs = 30_000;

  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  async load(ctx: WatchStoreContext): Promise<PagosRow[]> {
    const sql = `
      WITH base AS (
        SELECT s.id,
               s.status,
               s.nullified_sale_id,
               ${saleBranchSql('s')} AS branch_id
          FROM sales s
         WHERE ${VENTAS_BASE_WHERE}
           AND ${VENTAS_DIA_SQL} = :hoy
      ),
      pagos AS (
        SELECT b.branch_id,
               'pago'::text AS kind,
               pm.slug::text AS slug,
               SUM(spm.amount) AS amount
          FROM base b
          JOIN sale_payment_methods spm ON spm.sale_id = b.id
          LEFT JOIN payment_methods pm ON pm.id = spm.payment_method_id
         GROUP BY b.branch_id, pm.slug
      ),
      favor_auto AS (
        SELECT b.branch_id,
               'favor_auto'::text AS kind,
               NULL::text AS slug,
               SUM(
                 CASE WHEN b.status = 'Anulación' THEN -cl.amount ELSE cl.amount END
               ) AS amount
          FROM base b
          JOIN credit_ledger cl
            ON cl.store_id = :storeId
           AND cl.movement_type = 'favor_apply'
           AND cl.parent_ledger_id IS NOT NULL
           AND cl.payment_id IS NULL
           AND cl.sale_id = CASE
                               WHEN b.status = 'Anulación' THEN b.nullified_sale_id
                               ELSE b.id
                             END
         GROUP BY b.branch_id
      )
      SELECT branch_id, kind, slug, amount FROM pagos
      UNION ALL
      SELECT branch_id, kind, slug, amount FROM favor_auto
    `;

    const rows = await this.sequelize.query<PagosQueryRow>(sql, {
      replacements: {
        storeId: ctx.storeId,
        tz: ctx.tz,
        hoy: ctx.clock.hoy,
        ayer: ctx.clock.ayer,
        accounting: ACCOUNTING_SALE_STATUSES,
      },
      type: QueryTypes.SELECT,
    });

    const byBranch = new Map<number | null, PagosRow>();
    const bucketRow = (branchId: number | null): PagosRow => {
      let row = byBranch.get(branchId);
      if (!row) {
        row = {
          branchId,
          efectivo: 0,
          bancarias: 0,
          credito: 0,
          favor: 0,
          otros: 0,
        };
        byBranch.set(branchId, row);
      }

      return row;
    };

    for (const r of rows) {
      const branchId = r.branch_id === null ? null : Number(r.branch_id);
      const amount = Number(r.amount ?? 0);
      const row = bucketRow(branchId);

      if (r.kind === 'pago') {
        const bucket: MedioDePagoWatch = medioDePagoWatch(r.slug);
        row[bucket] += amount;
      } else {
        // favor_auto — 재배분이다, 새 돈이 아니다: 칸 사이에서 credito → favor 로
        // 옮긴다(다섯 칸의 합은 변하지 않는다, 음수면 반대 방향).
        row.favor += amount;
        row.credito -= amount;
      }
    }

    return [...byBranch.values()];
  }
}
import { Injectable } from '@nestjs/common';
import { InjectConnection } from '@nestjs/sequelize';
import { QueryTypes, Sequelize } from 'sequelize';

import {
  ingresoLedgerNoteSql,
  STOCK_TYPE,
} from '../../../stocks/stocks.constants';
import {
  IngresosRow,
  WatchSource,
  WatchStoreContext,
} from '../watch-resumen.contract';

// =============================================================================
// [Phase 98-09, D-12 ③·D-15 ④·⑤] `ingresos` 원천 — ④ Ingresos 의 매입 + 공방
// 수령만 `stocks` 원장 **한 문장**으로 계산한다.
// =============================================================================
// Ventago 에는 매입 전표 테이블이 없다 — **매입 = 수동 재고 입고**(`type IS NULL`,
// `source = 'legacy_opening'` 제외 — 그건 레거시 이관 기초재고라 매입이 아니다) +
// 시스템이 쓴 입고 취소·정정(`type='adjust'`, `ingresoLedgerNoteSql` — stocks.constants.ts
// 의 단일 출처, `v_product_branch_daily_ingreso` 의 net 과 같은 정의).
//
// 제외: 사람 보정(`adjust`, source `manual_adjust`) · 지점 간 이동(`transfer`) ·
// 판매/취소 역분개(`sale`) · 보류(`suspend`) · 반품(`devolucion`) · 폐기(`writeoff`) ·
// 자체 생산(work-order.service.ts 의 `consumo OT#`/`ingreso OT#` — MES 생산, 공방 아님).
//
// 공방 수령 경로는 셋(recepcion.service.ts 최종 공정 수령·lote.service.ts 수동 보정·
// recepcion.service.ts 수령 취소 — memory: talleres-recepciones-has-three-writers)이지만
// **원장 쓰기는 ingresarStockPorProductos/ingresarStockPorMatrix 하나**
// (productStock.service.ts 의 writeStockRows, memory: prod-stock-entry-is-reception-driven)
// 라 note 접두어 하나로 셋을 전부 잡을 수 있다.
//
// ★ 입고 건수(eventos) = D-15 ④ 그날 입고된 **모델(코드 마드레) 수**
//   (`COALESCE(p.parent_id, p.id)` — reportsIngresoCockpit.service.ts 의 product_count
//   와 같은 정의).
// =============================================================================

/**
 * 공방 수령 note 접두어 — 쓰는 쪽(recepcion.service.ts·lote.service.ts) 문구의
 * **단일 출처**. 세 곳이 같은 문자열을 공유하므로 쓰는 쪽 문구가 바뀌면
 * `taller-notes.spec.ts` 가 죽어 워치 집계가 조용히 0 이 되는 사고를 막는다.
 */
export const TALLER_NOTE_PREFIXES = [
  'Recepción lote ',
  'Ingreso manual (corrección) lote ',
  'Reversa ingreso recepción ',
] as const;

/** `note LIKE '접두어%'` 를 OR 로 묶는다 — stocks.constants.ts 의 noteLikeAnySql 과 같은 방식. */
const noteLikeAnySql = (alias: string, prefixes: readonly string[]): string =>
  `(${alias}.note IS NOT NULL AND (${prefixes
    .map((p) => `${alias}.note LIKE '${p.replace(/'/g, "''")}%'`)
    .join(' OR ')}))`;

/** 매입 — 수동 재고 입고(레거시 이관 제외) + 시스템 입고 정정/취소. */
const COMPRA_SQL = `((s.type IS NULL AND COALESCE(s.source, '') <> 'legacy_opening') OR (s.type = '${STOCK_TYPE.ADJUST}' AND ${ingresoLedgerNoteSql('s')}))`;

/** 공방 수령 — production 행 중 쓰는 쪽 note 접두어에 해당하는 것만(자체 생산 OT 제외). */
const TALLER_SQL = `(s.type = '${STOCK_TYPE.PRODUCTION}' AND ${noteLikeAnySql('s', TALLER_NOTE_PREFIXES)})`;

interface IngresosQueryRow {
  branch_id: number | null;
  compras_prendas: string | null;
  compras_eventos: string | null;
  talleres_prendas: string | null;
  talleres_eventos: string | null;
}

@Injectable()
export class IngresosSource implements WatchSource<'ingresos', IngresosRow> {
  readonly key = 'ingresos' as const;
  readonly periodo = 'hoy' as const;
  readonly ttlMs = 30_000;

  constructor(@InjectConnection() private readonly sequelize: Sequelize) {}

  async load(ctx: WatchStoreContext): Promise<IngresosRow[]> {
    // [98-10, CODEX P2] eventos(모델 수)는 **모델별 그날 순수량**이 양수인
    // 것만 센다 — 행 단위로 "stock>0 인 행이 하나라도 있으면" 세면, 같은 날
    // 수령(+N)과 그 취소(−N)가 함께 있는 모델이 순수량 0 인데도 eventos 에
    // 남는다(원본 수령 행 자체는 stock>0 이므로). 그래서 modelo_net 에서
    // 먼저 모델별로 순수량을 합산한 뒤, 그 순수량으로 eventos 를 센다.
    const sql = `
      WITH base AS (
        SELECT s.branch_id,
               COALESCE(p.parent_id, p.id) AS modelo_id,
               s.stock,
               (${COMPRA_SQL}) AS es_compra,
               (${TALLER_SQL}) AS es_taller
          FROM stocks s
          JOIN "ProductBranch" pb ON pb.id = s.product_branch_id
          JOIN products p ON p.id = pb.product_id AND p.store_id = :storeId
         WHERE s.store_id = :storeId
           AND s.operation_date = :hoy
           AND (${COMPRA_SQL} OR ${TALLER_SQL})
      ),
      modelo_net AS (
        SELECT branch_id,
               modelo_id,
               SUM(stock) FILTER (WHERE es_compra) AS compra_net,
               SUM(stock) FILTER (WHERE es_taller) AS taller_net
          FROM base
         GROUP BY branch_id, modelo_id
      )
      SELECT branch_id AS branch_id,
             COALESCE(SUM(compra_net), 0) AS compras_prendas,
             COUNT(*) FILTER (WHERE compra_net > 0) AS compras_eventos,
             COALESCE(SUM(taller_net), 0) AS talleres_prendas,
             COUNT(*) FILTER (WHERE taller_net > 0) AS talleres_eventos
        FROM modelo_net
       GROUP BY branch_id
    `;

    const rows = await this.sequelize.query<IngresosQueryRow>(sql, {
      replacements: { storeId: ctx.storeId, hoy: ctx.clock.hoy },
      type: QueryTypes.SELECT,
    });

    return rows.map((r) => ({
      branchId: r.branch_id === null ? null : Number(r.branch_id),
      comprasPrendas: Number(r.compras_prendas ?? 0),
      comprasEventos: Number(r.compras_eventos ?? 0),
      talleresPrendas: Number(r.talleres_prendas ?? 0),
      talleresEventos: Number(r.talleres_eventos ?? 0),
    }));
  }
}

codex
- P1: 수정됨 — `TenantContext.storeId === device.storeId`를 명시적으로 검증함.
- P2: 수정됨 — 모델별 순수량을 먼저 합산하고 양수인 모델만 `eventos`로 계산함.
- P3: 새 결함 없음.
tokens used
16,818
- P1: 수정됨 — `TenantContext.storeId === device.storeId`를 명시적으로 검증함.
- P2: 수정됨 — 모델별 순수량을 먼저 합산하고 양수인 모델만 `eventos`로 계산함.
- P3: 새 결함 없음.
```
