-- ============================================================
-- 스테이지 안전화 (운영 데이터 복제 직후 반드시 실행)
-- ============================================================
-- 왜 필요한가:
--   운영 DB 를 그대로 복제하면 **실제 고객 연락처와 실제 결제 자격증명**이
--   스테이지에 들어온다. 이 상태로 앱을 띄우면 스테이지가
--     · 실제 고객에게 WhatsApp/이메일 캠페인을 보내고
--     · 실제 Mercadopago 계정으로 결제·환불을 일으키고
--     · 운영 매장의 comandera/Zebra 프린터로 전표를 출력하고
--     · 운영 WooCommerce 로 재고 동기화를 밀어넣을
--   수 있다. 전부 되돌릴 수 없는 사고다.
--
-- 이 스크립트는 그 경로들을 DB 레벨에서 끊는다.
-- 앱 레벨 스위치(CRON_ENABLED=false 등)와 **이중으로** 건다 — 한쪽이 뚫려도 막히도록.
--
-- 실행: psql -v ON_ERROR_STOP=1 --single-transaction -f stage-sanitize.sql
-- ============================================================

\set ON_ERROR_STOP on

DO $$
BEGIN
  -- 실수로 운영 DB 에 돌리는 것을 막는 안전핀.
  -- 04-restore.sh 가 복원 직후 이 마커를 심는다.
  IF NOT EXISTS (
    SELECT 1 FROM pg_class WHERE relname = '_stage_marker' AND relkind = 'r'
  ) THEN
    RAISE EXCEPTION
      '_stage_marker 테이블이 없습니다. 이 DB 는 스테이지가 아닐 수 있습니다 — 중단합니다.';
  END IF;
END
$$;

-- ── 1. Mercadopago: 운영 토큰 무효화 + sandbox 강제 ──────────
-- access_token/refresh_token 은 NOT NULL 이므로 지울 수 없다 → 형식만 유지한 무효값으로 덮는다.
UPDATE mp_accounts
SET access_token    = 'STAGE_DISABLED',
    refresh_token   = 'STAGE_DISABLED',
    public_key      = NULL,
    environment     = 'sandbox',
    disconnected_at = COALESCE(disconnected_at, now()),
    updated_at      = now();

UPDATE subscription_config
SET enabled           = false,
    mp_access_token   = NULL,
    stripe_secret_key = NULL;

-- ── 2. 아웃바운드 메시징: WhatsApp / 이메일 ──────────────────
UPDATE store_whatsapp_config
SET access_token = NULL,
    is_active    = false;

UPDATE store_configs
SET email_api_key_enc = NULL,
    email_api_url     = NULL;

-- Telegram 알림 대상 제거 (운영 채팅방으로 스테이지 알림이 가는 것을 막는다)
UPDATE stores
SET telegram_chat_id = NULL;

-- ── 3. 캠페인: 예약/진행 중인 것을 전부 정지 ─────────────────
UPDATE campaigns
SET status       = 'draft',
    scheduled_at = NULL,
    updated_at   = now()
WHERE status NOT IN ('draft', 'done', 'completed', 'cancelled');

-- ── 4. 외부 커머스 동기화(WooCommerce/WP) 차단 ───────────────
-- site_url 까지 무효화한다. is_active 만 끄면 누군가 UI 에서 다시 켤 때
-- 곧바로 운영 쇼핑몰로 쓰기가 나간다.
UPDATE commerce_channels
SET is_active          = false,
    secret             = 'STAGE_DISABLED',
    wc_consumer_secret = NULL,
    site_url           = 'https://stage.invalid';

UPDATE wp_channels
SET is_active          = false,
    secret             = 'STAGE_DISABLED',
    wc_consumer_secret = NULL,
    site_url           = 'https://stage.invalid';

-- 미처리 아웃박스는 전부 취소. 워커가 뜨는 순간 운영 쇼핑몰로 밀어넣는다.
UPDATE sync_outbox
SET status       = 'cancelled',
    last_error   = 'stage sanitize: 운영 대상 발신 차단',
    processed_at = now(),
    updated_at   = now()
WHERE status IN ('pending', 'processing', 'failed');

-- ── 5. 프린터/디바이스 에이전트 키 재발급 ────────────────────
-- ★ 가장 위험한 항목이다. 키를 그대로 두면 운영 매장에 설치된 print-agent 가
--   스테이지에도 붙을 수 있고(또는 그 반대), 스테이지 테스트 판매 전표가
--   실제 매장 프린터에서 나온다.
UPDATE branch_agents
SET api_key      = 'stg_' || encode(gen_random_bytes(28), 'hex'),
    is_online    = false,
    socket_id    = NULL,
    last_seen_at = NULL,
    updated_at   = now();

UPDATE branch_printer_configs
SET api_key = 'stg_' || encode(gen_random_bytes(28), 'hex');

UPDATE branches
SET api_key = 'stg_' || encode(gen_random_bytes(28), 'hex')
WHERE api_key IS NOT NULL;

UPDATE despacho_devices
SET api_key = 'stg_' || encode(gen_random_bytes(28), 'hex');

UPDATE vendedor_devices
SET api_key = 'stg_' || encode(gen_random_bytes(28), 'hex');

-- ── 6. 세션 초기화 ───────────────────────────────────────────
-- 운영 세션 토큰이 살아 있으면 스테이지에서 그대로 인증이 통과한다.
-- active_sessions 는 유저당 1행(UNIQUE) 구조라, 비워야 스테이지 로그인이 깨끗하다.
TRUNCATE TABLE active_sessions RESTART IDENTITY;
TRUNCATE TABLE mobile_sessions RESTART IDENTITY;
TRUNCATE TABLE support_tokens RESTART IDENTITY;
TRUNCATE TABLE pending_registrations RESTART IDENTITY;

-- terminal_devices / branch_ip_registries 는 남긴다.
-- 새 IP·새 디바이스로 접속하면 앱이 등록 모달을 띄우는 것이 **설계된 동작**이고,
-- 스테이지에서 그 플로우 자체를 검증할 수 있어야 하기 때문이다.

-- ── 7. 스테이지 표식 ─────────────────────────────────────────
-- 화면에서 운영과 혼동하지 않도록 매장 별칭에 접두어를 단다.
UPDATE stores
SET alias_name = '[STAGE] ' || COALESCE(alias_name, name, '')
WHERE alias_name IS NULL OR alias_name NOT LIKE '[STAGE]%';

-- ── 8. 결과 요약 ─────────────────────────────────────────────
\echo ''
\echo '── 안전화 결과 ──'
SELECT 'mp_accounts (live token 남음)' AS check,
       count(*) AS must_be_zero
FROM mp_accounts WHERE access_token <> 'STAGE_DISABLED'
UNION ALL
SELECT 'commerce_channels (active)', count(*) FROM commerce_channels WHERE is_active
UNION ALL
SELECT 'wp_channels (active)', count(*) FROM wp_channels WHERE is_active
UNION ALL
SELECT 'sync_outbox (pending)', count(*) FROM sync_outbox WHERE status IN ('pending','processing')
UNION ALL
SELECT 'store_whatsapp_config (active)', count(*) FROM store_whatsapp_config WHERE is_active
UNION ALL
SELECT 'stores (telegram 남음)', count(*) FROM stores WHERE telegram_chat_id IS NOT NULL
UNION ALL
SELECT 'active_sessions', count(*) FROM active_sessions
UNION ALL
SELECT 'campaigns (예약중)', count(*) FROM campaigns WHERE scheduled_at IS NOT NULL;
