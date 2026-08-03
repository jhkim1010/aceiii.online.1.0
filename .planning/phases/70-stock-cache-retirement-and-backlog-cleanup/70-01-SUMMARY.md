---
phase: 70-stock-cache-retirement-and-backlog-cleanup
plan: 01
status: complete
verdict: GO (Inspector, Major 2件は後続タスク 010 へ)
date: 2026-08-03
requirements: [R1]
---

# 70-01 — 在庫読み取りを `stock_balances` / ビューへ移行

## 何をしたか

在庫数量を **読む** 経路を `products.stock` キャッシュから `stock_balances` スナップショット
および インターフェースビューへ移した。**読み取り移行のみ** — トリガー
`trg_stocks_sync_product_cache` と `products.stock` カラム、および `products.stock` への
書き込み経路には一切触れていない（廃止は 70-06）。

`products.stock` は商品あたり数値ひとつで **支店次元を持たない**。多支店店舗で
「この支店に何個あるか」には元々答えられず、コードがそれを支店別在庫として使っている
箇所が残っていた。`stock_balances` は `ProductBranch` 単位なのでこの問いに正確に答える。

## T1 — `products.stock` 読み取り経路 全数調査

`api-ventago/src` 全体を走査し、コメントを除いた実コードを 読み取り / 書き込み / テスト に分類した。

### 移行した読み取り経路（本タスクの範囲）

| ファイル | 行 | 性質 | 移行先 | 判断根拠 |
|---|---|---|---|---|
| `sales/sales-create.service.ts` | 1173〜 (`applyStockLedger`) | ★ 販売の在庫検証（コミット直前の `FOR UPDATE`） | `stock_balances.available`（`store_id`+`branch_id`+`product_id`） | 販売が実際に問うのは「**この支店**に在庫があるか」。旧 `products.stock` は全支店合計なので支店 A 0 / 支店 B 10 の商品を A で売っても通っていた |
| `sales/sales-create.service.ts` | 1299〜 (`validateAndCalculateItems`) | 早期失敗の UX 用検証 | 同上（支店未解決時は `v_stock_total_variante.available`） | 支店を特定できない経路では旧 `products.stock`（＝全支店合計）と同じ範囲を見る |
| `products/products.service.ts` | 826 | 支店ラベル出力の `cantidad` | `stock_balances.available`（`branch_id` 絞り込み） | この照会自体が `branchId` で絞られた**支店ラベル用**。旧実装は他支店の在庫まで載った数値をラベルに印字していた |
| `products/productStock.service.ts` | 1028 | POS 検索結果（codigo hijito）の `stock` | 支店あり → `stock_balances` / 支店なし → `v_stock_total_variante` | POS 検索は「今売っている支店に何個」が正しい問い |
| `products/productStock.service.ts` | 1099〜 (`findByParentFlag`) | variant × 支店の在庫分布 | `stock_balances`（`product_id`, `branch_id`, `available`） | 旧 `ProductBranch JOIN stocks GROUP BY` の置換。`ProductBranch` は `UNIQUE(product_id, branch_id)` なのでスナップショット 1 行 = 支店 1 個で 1:1 |
| `products/productStock.service.ts` | 1213〜 (`GET /products/:id/inventory`) | マドレ単位の在庫概要 | `v_stock_total_variante.available`（**全支店合計**） | このエンドポイントは支店パラメータを取らず、旧 `products.stock` も全支店合計だった。支店別が要る画面は `live-stock/by-parent` を使う |
| `products/productStock.service.ts` | 1270〜 (`getLiveStockByParent`) | POS でマドレ選択時の live 在庫 | `stock_balances` | `findByParentFlag` と同一ソースに揃えた |

### 変更不要と判定したもの

| ファイル | 理由 |
|---|---|
| `online-orders/online-order-stock.service.ts` | PLAN の候補に挙がっていたが、`products.stock` の言及は**すべてコメント**。実コードは `stocks` 原簿 INSERT のみで読み取りが無い |
| `stocks/stocks.service.ts`, `stocks.model.ts`, `subcon-material-issue.service.ts` | コメントのみ |
| `productStock.service.ts:1596` | `row.stock` は `stocks` 原簿行であって `products.stock` ではない |

### ★ 未移行のまま残った読み取り（範囲外 → タスク **010** で対応。70-06 の前提条件）

| ファイル | 行 | 性質 |
|---|---|---|
| `shop-public/shop-catalog.service.ts` | 98 / 132 / 151 / 173 | 公開カタログの在庫表示 + `showOutOfStock=false` 時の `COALESCE(p.stock,0) > 0` 絞り込み |
| `revendedor/purchase/revendedor-purchase.service.ts` | 192 | ★ 購入遮断ガード `product.stock < item.quantity` |
| `revendedor/products/revendedor-products.service.ts` | 173 / 237 | `inStock: p.stock > 0` |
| `code-import/code-import.service.ts` | 794 | `Number(found.stock ?? 0)` を import 後在庫の基準線に使用 |
| `sales/sales.service.ts` | 335 / 599 / 789 / 940 | 販売照会レスポンスの `attributes` に `'stock'` を素通し |

これらは 70-01 の `files_modified`（5ファイル）範囲外だったため、範囲を勝手に広げず
別タスクに切り出した。**`products.stock` カラムを落とす 70-06 の前に必ず片付けること。**

## 意味論の等価性検証（置換が数値的に安全であることの根拠）

旧 `COALESCE(SUM(s.stock), 0)` を `stock_balances.available` に置き換えたので、
両者が一致するかをローカル DB の実データ全件で照合した。

```sql
SELECT count(*) FROM (
  SELECT pb.product_id, pb.branch_id, COALESCE(SUM(s.stock),0) AS ledger
    FROM "ProductBranch" pb JOIN stocks s ON s.product_branch_id = pb.id
   GROUP BY pb.product_id, pb.branch_id) L
  JOIN stock_balances sb
    ON sb.product_id = L.product_id AND sb.branch_id = L.branch_id
 WHERE sb.available <> L.ledger;
-- → 0 件（全 642 行一致）
```

補足: `available = on_hand - reservado` は全 642 行で成立（不一致 0）。
`reservado <> 0` の行は 26 件あるが、それらも含めて `available == SUM(stocks.stock)` が
成立している（予約は原簿にマイナス行として既に反映済みで、`on_hand` がそれを戻している）。
したがって **置換による数値の変化は無い**。

## 変更ファイル

```
src/app/products/productStock.service.ts    |  88 ++++++++++++++++----
src/app/products/products.service.ts        |  27 ++++++-
src/app/sales/sales-create.service.ts       | 116 +++++++++++++++++++++++---
src/app/sales/sales-stock-decrement.spec.ts |  21 ++++-
src/app/sales/sales-stock-guard.spec.ts     | 115 +++++++++++++++++++++++---
5 files changed, 327 insertions(+), 40 deletions(-)
```

`sales-stock-decrement.spec.ts` は `applyStockLedger` に必須引数 `storeId` を追加したことに
伴う機械的なシグネチャ更新のみ（PLAN の `files_modified` には無いが、追加せずには
コンパイルが通らない）。

## 在庫ポリシーの維持（回帰防止）

- 在庫超過販売の遮断は `allowSaleWithoutStock === false` の店舗のみ。両検証とも
  `if (!allowSaleWithoutStock)` の内側にあり、**許可店舗では在庫クエリ自体が走らない**
  （テストで `expect(sequelize.query).not.toHaveBeenCalled()` として固定）
- `isGeneric` の例外を維持
- ロック順は `productId` 昇順 — ループ廃止に伴い、単一文の `ORDER BY product_id ... FOR UPDATE`
  で文内の取得順を固定
- `stocks` は append-only のまま。UPDATE/DELETE の追加なし
- N+1 解消: 品目数によらず 1 クエリ（`product_id = ANY($n::int[])`）
- `storeId` を `applyStockLedger` の**必須**引数に昇格（省略可にすると呼び出し漏れ時に
  他店舗の残高で検証が通ってしまう）

## T4 — 追加した回帰テスト（`sales-stock-guard.spec.ts`）

- `allowSaleWithoutStock=false` + `available` 0 → 遮断
- スナップショット行そのものが無い（その支店に入庫履歴なし）→ 가용 0 とみなし遮断
- `allowSaleWithoutStock=true` + `available` −20 → **通過**（ポリシー。クエリも走らない）
- 支店 A 在庫 0 / 支店 B 在庫 10 → A は遮断・B は通過
  （`products.stock` 合計では区別できなかったケース）
- 複数商品でも 1 クエリ（N+1 禁止の固定）
- SQL 形状の固定: `FROM stock_balances` / `FOR UPDATE` / `store_id = $1` / `branch_id = $2` /
  `ORDER BY product_id`、および `not.toContain('FROM products')`

## T5 — 検証結果

| 項目 | 着手前 | 着手後 | 判定 |
|---|---|---|---|
| `npx tsc --noEmit -p tsconfig.build.json` | 0 errors | 0 errors | ✅ |
| jest 対象 suite | 5 suites / 20 tests failed (of 62) | 5 suites / 20 tests failed (of 73) | ✅ **新規失敗 0** |
| `sales-stock-guard.spec.ts` | 0 failed / 11 passed | 0 failed / **17 passed** | ✅ +6 |
| `sales-stock-decrement.spec.ts` | — | 0 failed / 5 passed | ✅ |
| `SELECT count(*) FROM v_stock_balance_drift` | 0 | 0 | ✅ |
| `SELECT count(*) FROM v_stock_tenant_leak` | 0 | 0 | ✅ |

既存失敗の内訳（**着手前から失敗しており本タスクの範囲外**、未修正）:
`productStock.service.spec` 14 / `products.service.spec` 5 / `stocks.service.spec` 1 /
`sales.controller.spec`・`suspended-sales.controller.spec` は suite ロード自体が失敗。

## Inspector 判定

**VERDICT: GO**（Critical なし）

- 移行そのものは正しい。ゲート条件・`isGeneric` 例外・ロック順・append-only・
  トリガー不可侵はすべて維持されている
- `available` の定義が旧 `products.stock` と数値的に一致することを実データで確認
- Major: 未移行の読み取りが 3 系統残る（上表）→ タスク **010** に切り出し。
  70-06 で列を落とす前の必須前提条件
- Major: `processSaleItems` 側（早期失敗パス）はテスト未カバー → タスク 010 で併せて対応

## 残課題

- **タスク 010** — 残存 `products.stock` 読み取り経路の移行（70-06 の前提条件）
- マイグレーション（DDL）は無し。本タスクはコード変更のみ
- 本番反映は未実施。**push は Master のレビュー後**（レビューゲートあり）
