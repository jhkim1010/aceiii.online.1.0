-- [Phase 88 · W4] **셋업 가이드가 실제로 듣는지 재는 쿼리.**
--
-- 돌리는 법:
--   ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -f -" < scripts/setup-guide-metrics.sql
--
-- ★★★ 재는 것은 **체크리스트 완료율이 아니다.** 그 값은 188개사 중앙값 10.1% 라
--   무엇도 구분하지 못한다(SPEC §측정). 보는 것은 둘이다:
--     ① **TTFV** — 가입에서 첫 판매까지 걸린 시간
--     ② **이탈 단계** — 사람들이 어디서 멈추는가
--
-- ★★ **「0건」과 「이상 없음」을 구분한다.** 이 원장은 사람이 홈에서 가이드를
--   열어야 채워진다. 아무도 안 열었으면 모든 지표가 0 인데, 그것을 「다들 잘
--   하고 있다」로 읽으면 정반대다. 그래서 ⓪ 이 먼저 나온다 —
--   **표본이 없다는 사실 자체를 먼저 말한다.**
--   (이 저장소가 「수집 0건은 위반 0건이 아니다」로 겪은 형태다.)

\echo ''
\echo '=== ⓪ 표본이 있는가 — 이것부터 본다 ==='
SELECT
  (SELECT count(*) FROM store_setup_events)                       AS eventos,
  (SELECT count(DISTINCT store_id) FROM store_setup_events)       AS tiendas_con_actividad,
  (SELECT count(*) FROM stores WHERE setup_hidden_at IS NULL)     AS tiendas_con_guia,
  CASE WHEN (SELECT count(*) FROM store_setup_events) = 0
       THEN '★ 원장이 비었다 — 아래 숫자는 「좋다」가 아니라 「모른다」다'
       ELSE 'ok'
  END AS lectura;

\echo ''
\echo '=== ① TTFV — 가입에서 첫 판매까지 ==='
-- ★ `store_setup_events` 의 `completed/first_sale` 이 **처음** 기록된 시각을 쓴다.
--   판매 자체의 시각이 아니다 — 가이드가 그것을 **인지한** 시점이라 지표의
--   단위가 「가이드가 본 세계」로 일관된다.
-- ★★ 아직 첫 판매가 없는 매장은 **제외하지 않고 따로 센다.** 빼면 TTFV 가
--   「해낸 사람들만의 평균」이 되어 좋아 보인다 — 이탈이 지표에서 사라진다.
WITH primera AS (
  SELECT e.store_id, min(e.occurred_at) AS vendio_en
    FROM store_setup_events e
   WHERE e.step_code = 'first_sale' AND e.event = 'completed'
   GROUP BY e.store_id
)
SELECT
  count(*) FILTER (WHERE p.vendio_en IS NOT NULL)                  AS llegaron,
  count(*) FILTER (WHERE p.vendio_en IS NULL)                      AS todavia_no,
  round(avg(EXTRACT(epoch FROM p.vendio_en - s.created_at) / 3600)
        FILTER (WHERE p.vendio_en IS NOT NULL)::numeric, 1)        AS horas_promedio,
  round((percentile_cont(0.5) WITHIN GROUP (
          ORDER BY EXTRACT(epoch FROM p.vendio_en - s.created_at) / 3600))::numeric, 1)
                                                                   AS horas_mediana
  FROM stores s
  LEFT JOIN primera p ON p.store_id = s.id;

\echo ''
\echo '=== ② 이탈 단계 — 어디서 멈추는가 ==='
-- ★ 「완료한 매장 수」가 아니라 **「아직 못 한 매장 수」**를 센다. 전자는 오래된
--   매장이 많을수록 좋아 보이고, 우리가 고쳐야 할 곳을 가리키지 않는다.
-- ★★ 「해당 없음」으로 끈 것은 이탈이 아니다 — 따로 센다. 섞으면 「프린터에서
--   다 막힌다」처럼 보이는데 실제로는 그냥 안 쓰는 기능일 수 있다.
SELECT
  c.step_code,
  count(*) FILTER (WHERE st.completed_at IS NOT NULL)              AS hechas,
  count(*) FILTER (WHERE st.dismissed_at IS NOT NULL)              AS no_aplica,
  count(*) FILTER (WHERE st.snoozed_until > now())                 AS pospuestas,
  count(*) FILTER (WHERE st.id IS NULL)                            AS sin_tocar
  FROM (VALUES
        ('load_products'), ('set_prices'), ('check_payment_methods'),
        ('connect_printer'), ('first_sale')
       ) AS c(step_code)
  CROSS JOIN stores s
  LEFT JOIN store_setup_steps st
         ON st.store_id = s.id AND st.step_code = c.step_code
 WHERE s.setup_hidden_at IS NULL
 GROUP BY c.step_code
 ORDER BY sin_tocar DESC;

\echo ''
\echo '=== ③ 지금 화면에 무엇이 뜨고 있나 (원장 없이도 나온다) ==='
-- ★ 이 블록만 **원장과 무관**하다 — 술어를 그 자리에서 다시 계산한다.
--   그래서 아무도 가이드를 안 열어도 「지금 상태」는 알 수 있다.
--   ②가 0 일 때 여기를 보면 「표본이 없다」와 「할 일이 없다」가 구분된다.
WITH p AS (
  SELECT s.id, s.created_at,
    (3
     + (EXISTS (SELECT 1 FROM products x
                 WHERE x.store_id = s.id AND COALESCE(x.is_generic,false) = false))::int
     + (EXISTS (SELECT 1 FROM price_types x WHERE x.store_id = s.id))::int
     + (EXISTS (SELECT 1 FROM payment_methods x
                 WHERE x.store_id = s.id
                   AND (x.slug NOT IN ('efectivo','tarjeta-debito','mercadopago')
                     OR x.is_active = false)))::int
     + (EXISTS (SELECT 1 FROM branch_agents a
                  JOIN branches b ON b.id = a.branch_id AND b.store_id = s.id
                 WHERE a.last_seen_at IS NOT NULL))::int
     + (EXISTS (SELECT 1 FROM sales v
                 WHERE v.store_id = s.id AND v.activity_type = 'sale'
                   AND v.nullified_by_sale_id IS NULL))::int
    ) AS hechos,
    (EXISTS (SELECT 1 FROM sales v
              WHERE v.store_id = s.id AND v.activity_type = 'sale'
                AND v.nullified_by_sale_id IS NULL)) AS vendio
    FROM stores s
   WHERE s.setup_hidden_at IS NULL
)
SELECT
  count(*) FILTER (WHERE NOT (hechos * 100.0 / 8 >= 70
                              AND now() - created_at > interval '7 days'))  AS ven_guia,
  count(*) FILTER (WHERE hechos * 100.0 / 8 >= 70
                         AND now() - created_at > interval '7 days')        AS auto_ocultas,
  count(*) FILTER (WHERE NOT (hechos * 100.0 / 8 >= 70
                              AND now() - created_at > interval '7 days')
                         AND vendio)                                        AS tono_aprovechar,
  count(*) FILTER (WHERE NOT (hechos * 100.0 / 8 >= 70
                              AND now() - created_at > interval '7 days')
                         AND NOT vendio)                                    AS tono_arranque
  FROM p;
