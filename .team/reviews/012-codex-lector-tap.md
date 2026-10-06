Reading additional input from stdin...
2026-10-06T17:32:55.587822Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/mobile-sales-app
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: read-only
reasoning effort: none
reasoning summaries: none
session id: 01a11246-8d33-7913-b446-26bf7711e82b
--------
user
Revisá este cambio Flutter (app vendedor). Pedido del usuario: en Modo lector la cámara NO debe sumar sola al carrito; cada toque en «+1» suma una unidad. Y un botón «Modo lector» debajo de «Ver carrito» en el inicio. Buscá bugs concretos (archivo:línea, escenario, arreglo). Español, breve.
diff --git a/lib/features/home/views/home_screen.dart b/lib/features/home/views/home_screen.dart
index 027730d..15bac9b 100644
--- a/lib/features/home/views/home_screen.dart
+++ b/lib/features/home/views/home_screen.dart
@@ -1,4 +1,4 @@
-// S1 Home (/home) — vendedor 랜딩. 3버튼(Buscar / Ver carrito / Escanear QR).
+// S1 Home (/home) — vendedor 랜딩. 4버튼(Buscar / Ver carrito / Modo lector / Escanear QR).
 // scope 로 "Hola, {nombre}" + 매장·지점 표시.
 // 출근 게이트(37-08): clockedIn=false 면 작업 버튼 잠금 + "Fichá tu entrada" + fichaje 버튼만.
 // 백엔드 RequireAttendanceGuard 가 권위 — 홈은 UX 미러링(라운드트립 절약).
@@ -323,6 +323,14 @@ class _WorkActionsState extends ConsumerState<_WorkActions> {
           badge: widget.cartUnits > 0 ? widget.cartUnits : null,
           onTap: () => context.push('/comanda'),
         ),
+        const SizedBox(height: 12),
+        // [2026-10-06] Modo lector — debajo de «Ver carrito»: leer la etiqueta y sumar con «+1»
+        _HomeButton(
+          emoji: '📷',
+          title: 'Modo lector',
+          subtitle: 'Leé la etiqueta y tocá +1 por unidad',
+          onTap: () => context.push('/lector'),
+        ),
         const Spacer(),
         // cliente (opcional) — QR 스캔 전에 이름부터 적는 플로우
         TextField(
@@ -406,6 +414,13 @@ class _ClockInGate extends StatelessWidget {
           subtitle: 'Fichá tu entrada para habilitar',
           disabled: true,
         ),
+        const SizedBox(height: 12),
+        const _HomeButton(
+          emoji: '📷',
+          title: 'Modo lector',
+          subtitle: 'Fichá tu entrada para habilitar',
+          disabled: true,
+        ),
         const Spacer(),
         _HomeButton(
           emoji: '🕑',
diff --git a/lib/features/scanner/views/lector_screen.dart b/lib/features/scanner/views/lector_screen.dart
index 228eeec..db5f682 100644
--- a/lib/features/scanner/views/lector_screen.dart
+++ b/lib/features/scanner/views/lector_screen.dart
@@ -1,4 +1,6 @@
-// [2026-10-05] Modo lector — la cámara queda abierta y cada código escaneado suma 1 al carrito.
+// [2026-10-05] Modo lector — la cámara queda abierta y muestra el producto leído.
+// [2026-10-06] Ya NO suma solo: el vendedor toca «+1» por cada unidad (usuario: «자동으로 읽지
+//   말고, 내가 클릭 할 때 하나씩 갯수를 올리는 것으로»). Leer sólo elige el producto.
 //
 // ★ Sólo variantes concretas (color/talle). Una madre (o el QR de la percha) no se agrega:
 //   no se sabe qué color/talle es — se ofrece abrir el detalle.
@@ -41,11 +43,22 @@ class LectorScreen extends ConsumerStatefulWidget {
   ConsumerState<LectorScreen> createState() => _LectorScreenState();
 }
 
+// El último producto leído, listo para sumar con «+1».
+class _Leido {
+  final String code;
+  final CartLine linea;
+  final String etiqueta;
+  final int stock;
+
+  const _Leido(this.code, this.linea, this.etiqueta, this.stock);
+}
+
 class _LectorScreenState extends ConsumerState<LectorScreen> {
   final MobileScannerController _controller = MobileScannerController();
   final Antirebote _antirebote = Antirebote();
   bool _ocupado = false;
   _Aviso? _aviso;
+  _Leido? _leido;
 
   @override
   void dispose() {
@@ -82,6 +95,10 @@ class _LectorScreenState extends ConsumerState<LectorScreen> {
     if (code.isEmpty || _ocupado || !_antirebote.aceptar(code, DateTime.now())) {
       return;
     }
+    // el mismo producto sigue en cuadro: ya está elegido, no hay nada que resolver
+    if (code == _leido?.code) {
+      return;
+    }
     _ocupado = true;
     try {
       await _procesar(code);
@@ -158,21 +175,35 @@ class _LectorScreenState extends ConsumerState<LectorScreen> {
       ownAvailable: tope,
       ownStock: v.stock,
     );
-    final res = ref.read(cartProvider.notifier).addScanned(linea);
     final etiqueta = '${r.name} · ${linea.colorName} / ${linea.sizeName}';
+    setState(() {
+      _leido = _Leido(code, linea, etiqueta, v.stock);
+      _aviso = null;
+    });
+    HapticFeedback.selectionClick();
+  }
+
+  // «+1» — una unidad por toque
+  void _sumar() {
+    final leido = _leido;
+    if (leido == null) {
+      return;
+    }
+    final res = ref.read(cartProvider.notifier).addScanned(leido.linea);
     if (res == ScanAdd.limite) {
-      _mostrar(_Aviso('Sin disponible: $etiqueta (stock ${v.stock})', _Tono.error));
+      _mostrar(_Aviso('Sin disponible: ${leido.etiqueta} (stock ${leido.stock})', _Tono.error));
 
       return;
     }
-    final enCarrito = ref
-        .read(cartProvider)
-        .lines
-        .firstWhere((l) => l.lineKey == linea.lineKey, orElse: () => linea)
-        .quantity;
-    _mostrar(_Aviso('✓ $etiqueta · +1 ($enCarrito)', _Tono.ok));
+    _mostrar(_Aviso('✓ ${leido.etiqueta} · +1 (${_enCarrito(leido)})', _Tono.ok));
   }
 
+  int _enCarrito(_Leido leido) => ref
+      .read(cartProvider)
+      .lines
+      .firstWhere((l) => l.lineKey == leido.linea.lineKey, orElse: () => leido.linea.copyWith(quantity: 0))
+      .quantity;
+
   void _verCarrito() {
     if (widget.desdeCarrito) {
       context.pop();
@@ -236,7 +267,7 @@ class _LectorScreenState extends ConsumerState<LectorScreen> {
                   left: 24,
                   right: 24,
                   child: Text(
-                    'Apuntá al código de barras o QR de la etiqueta. Cada lectura suma 1.',
+                    'Apuntá al código de barras o QR de la etiqueta y tocá «+1» por cada unidad.',
                     textAlign: TextAlign.center,
                     style: TextStyle(color: Color(0xFFB9B9C6), fontSize: 13),
                   ),
@@ -244,6 +275,7 @@ class _LectorScreenState extends ConsumerState<LectorScreen> {
               ],
             ),
           ),
+          if (_leido != null) _TarjetaLeido(leido: _leido!, enCarrito: _enCarrito(_leido!), onSumar: _sumar),
           SafeArea(
             top: false,
             child: Container(
@@ -281,6 +313,59 @@ class _LectorScreenState extends ConsumerState<LectorScreen> {
   }
 }
 
+// Producto leído + botón grande «+1» (cada toque suma una unidad)
+class _TarjetaLeido extends StatelessWidget {
+  final _Leido leido;
+  final int enCarrito;
+  final VoidCallback onSumar;
+
+  const _TarjetaLeido({required this.leido, required this.enCarrito, required this.onSumar});
+
+  @override
+  Widget build(BuildContext context) {
+    return Container(
+      color: AppColors.navy2,
+      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
+      child: Row(
+        children: [
+          Expanded(
+            child: Column(
+              crossAxisAlignment: CrossAxisAlignment.start,
+              children: [
+                Text(
+                  leido.etiqueta,
+                  maxLines: 2,
+                  overflow: TextOverflow.ellipsis,
+                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
+                ),
+                const SizedBox(height: 4),
+                Text(
+                  '${formatMoney(leido.linea.price)} · en carrito: $enCarrito',
+                  style: const TextStyle(color: Color(0xFFB9B9C6), fontSize: 13, fontFeatures: kTabularFigures),
+                ),
+              ],
+            ),
+          ),
+          const SizedBox(width: 12),
+          SizedBox(
+            width: 96,
+            height: 56,
+            child: FilledButton(
+              style: FilledButton.styleFrom(
+                backgroundColor: AppColors.gold,
+                foregroundColor: AppColors.navy2,
+                textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
+              ),
+              onPressed: onSumar,
+              child: const Text('+1'),
+            ),
+          ),
+        ],
+      ),
+    );
+  }
+}
+
 class _Banner extends StatelessWidget {
   final _Aviso aviso;
   final VoidCallback? onAbrir;
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
hook: SessionStart
hook: SessionStart Completed
hook: UserPromptSubmit
hook: UserPromptSubmit Completed
codex
Voy a contrastar el diff con el estado real del scanner, carrito y layout para señalar fallas reproducibles, no sólo riesgos teóricos.
hook: PreToolUse
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,470p' lib/features/scanner/views/lector_screen.dart && sed -n '280,450p' lib/features/home/views/home_screen.dart && rg -n \"class Antirebote|addScanned|class CartLine|copyWith\\(\" lib" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/mobile-sales-app
 succeeded in 0ms:
// [2026-10-05] Modo lector — la cámara queda abierta y muestra el producto leído.
// [2026-10-06] Ya NO suma solo: el vendedor toca «+1» por cada unidad (usuario: «자동으로 읽지
//   말고, 내가 클릭 할 때 하나씩 갯수를 올리는 것으로»). Leer sólo elige el producto.
//
// ★ Sólo variantes concretas (color/talle). Una madre (o el QR de la percha) no se agrega:
//   no se sabe qué color/talle es — se ofrece abrir el detalle.
// ★ Antirrebote por código (1,5 s): la cámara lee el mismo código varias veces por pasada.
// ★ Precio = el de la madre (como el catálogo/detalle); tope = misma regla que el detalle.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/format/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/scope_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../../product/data/stock_dto.dart';
import '../../product/data/stock_repository.dart';
import '../data/scan_repository.dart';
import '../logic/lector_logic.dart';
import 'qr_scanner_sheet.dart' show parseStockDeeplink;

enum _Tono { ok, aviso, error }

class _Aviso {
  final String texto;
  final _Tono tono;
  // madre / QR de percha: botón «Abrir» al detalle
  final int? abrirProductId;

  const _Aviso(this.texto, this.tono, {this.abrirProductId});
}

class LectorScreen extends ConsumerStatefulWidget {
  // abierto desde el carrito → «Ver carrito» vuelve atrás en vez de apilar otro carrito
  final bool desdeCarrito;

  const LectorScreen({super.key, this.desdeCarrito = false});

  @override
  ConsumerState<LectorScreen> createState() => _LectorScreenState();
}

// El último producto leído, listo para sumar con «+1».
class _Leido {
  final String code;
  final CartLine linea;
  final String etiqueta;
  final int stock;

  const _Leido(this.code, this.linea, this.etiqueta, this.stock);
}

class _LectorScreenState extends ConsumerState<LectorScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final Antirebote _antirebote = Antirebote();
  bool _ocupado = false;
  _Aviso? _aviso;
  _Leido? _leido;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _allowSaleWithoutStock {
    final scope = ref.read(scopeNotifierProvider).value;

    return switch (scope) {
      BranchScope(:final user) => user.allowSaleWithoutStock,
      MultiStoreScope(:final user) => user.allowSaleWithoutStock,
      _ => true,
    };
  }

  void _mostrar(_Aviso a) {
    if (!mounted) {
      return;
    }
    setState(() => _aviso = a);
    if (a.tono == _Tono.ok) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    final code = raw?.trim() ?? '';
    if (code.isEmpty || _ocupado || !_antirebote.aceptar(code, DateTime.now())) {
      return;
    }
    // el mismo producto sigue en cuadro: ya está elegido, no hay nada que resolver
    if (code == _leido?.code) {
      return;
    }
    _ocupado = true;
    try {
      await _procesar(code);
    } finally {
      _ocupado = false;
    }
  }

  Future<void> _procesar(String code) async {
    // QR de la percha (deeplink a la madre) — no dice color/talle
    final madreQr = parseStockDeeplink(code);
    if (madreQr != null) {
      _mostrar(_Aviso('Código de percha: elegí color y talle', _Tono.aviso, abrirProductId: madreQr));

      return;
    }

    final ScanResult r;
    try {
      r = await ref.read(scanRepositoryProvider).resolve(code);
    } on ApiException catch (e) {
      _mostrar(_Aviso(
        switch (e.code) {
          'SCAN_NOT_FOUND' => 'Código no encontrado: $code',
          'SCAN_AMBIGUOUS' => 'Hay más de un producto con el código $code — cargalo desde el catálogo',
          _ => e.message,
        },
        _Tono.error,
      ));

      return;
    }

    // ★ sin precio no se agrega: entraría como línea gratis
    if (r.price <= 0) {
      _mostrar(_Aviso('${r.name}: sin precio cargado — abrilo para revisarlo', _Tono.aviso, abrirProductId: r.productId));

      return;
    }

    if (r.necesitaVariante) {
      _mostrar(_Aviso('${r.name}: elegí color y talle', _Tono.aviso, abrirProductId: r.productId));

      return;
    }

    StockResult? stock;
    try {
      stock = await ref.read(stockRepositoryProvider).getStock(r.productId);
    } on ApiException catch (e) {
      _mostrar(_Aviso(e.message, _Tono.error));

      return;
    }
    final v = buscarVariante(stock.stockByVariant, r.colorId, r.sizeId);
    if (v == null) {
      // producto sin variantes, o variante que no aparece en el stock: el detalle lo resuelve
      _mostrar(_Aviso('${r.name}: abrilo para cargarlo', _Tono.aviso, abrirProductId: r.productId));

      return;
    }

    final tope = topeDisponible(v, allowSaleWithoutStock: _allowSaleWithoutStock);
    final linea = CartLine(
      productId: r.productId,
      productName: r.name,
      price: r.price,
      colorId: v.color.id,
      colorName: v.color.name ?? '—',
      colorHex: null,
      sizeId: v.size.id,
      sizeName: v.size.name ?? '—',
      quantity: 1,
      ownAvailable: tope,
      ownStock: v.stock,
    );
    final etiqueta = '${r.name} · ${linea.colorName} / ${linea.sizeName}';
    setState(() {
      _leido = _Leido(code, linea, etiqueta, v.stock);
      _aviso = null;
    });
    HapticFeedback.selectionClick();
  }

  // «+1» — una unidad por toque
  void _sumar() {
    final leido = _leido;
    if (leido == null) {
      return;
    }
    final res = ref.read(cartProvider.notifier).addScanned(leido.linea);
    if (res == ScanAdd.limite) {
      _mostrar(_Aviso('Sin disponible: ${leido.etiqueta} (stock ${leido.stock})', _Tono.error));

      return;
    }
    _mostrar(_Aviso('✓ ${leido.etiqueta} · +1 (${_enCarrito(leido)})', _Tono.ok));
  }

  int _enCarrito(_Leido leido) => ref
      .read(cartProvider)
      .lines
      .firstWhere((l) => l.lineKey == leido.linea.lineKey, orElse: () => leido.linea.copyWith(quantity: 0))
      .quantity;

  void _verCarrito() {
    if (widget.desdeCarrito) {
      context.pop();
    } else {
      context.pushReplacement('/comanda');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final aviso = _aviso;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Modo lector', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Container(
                  width: 260,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                if (aviso != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _Banner(
                      aviso: aviso,
                      onAbrir: aviso.abrirProductId == null
                          ? null
                          : () => context.push('/product/${aviso.abrirProductId}'),
                    ),
                  ),
                const Positioned(
                  bottom: 16,
                  left: 24,
                  right: 24,
                  child: Text(
                    'Apuntá al código de barras o QR de la etiqueta y tocá «+1» por cada unidad.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB9B9C6), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          if (_leido != null) _TarjetaLeido(leido: _leido!, enCarrito: _enCarrito(_leido!), onSumar: _sumar),
          SafeArea(
            top: false,
            child: Container(
              color: AppColors.navy,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${cart.totalUnits} u. · ${formatMoney(cart.subtotal)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.navy2,
                    ),
                    onPressed: _verCarrito,
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                    label: const Text('Ver carrito'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Producto leído + botón grande «+1» (cada toque suma una unidad)
class _TarjetaLeido extends StatelessWidget {
  final _Leido leido;
  final int enCarrito;
  final VoidCallback onSumar;

  const _TarjetaLeido({required this.leido, required this.enCarrito, required this.onSumar});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy2,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leido.etiqueta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatMoney(leido.linea.price)} · en carrito: $enCarrito',
                  style: const TextStyle(color: Color(0xFFB9B9C6), fontSize: 13, fontFeatures: kTabularFigures),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.navy2,
                textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              onPressed: onSumar,
              child: const Text('+1'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final _Aviso aviso;
  final VoidCallback? onAbrir;

  const _Banner({required this.aviso, this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final color = switch (aviso.tono) {
      _Tono.ok => AppColors.green,
      _Tono.aviso => AppColors.goldDark,
      _Tono.error => AppColors.red,
    };

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                aviso.texto,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            if (onAbrir != null)
              TextButton(
                onPressed: onAbrir,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Abrir'),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkActionsState extends ConsumerState<_WorkActions> {
  final _clientController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _clientController.text = ref.read(cartProvider).clientName;
  }

  @override
  void dispose() {
    _clientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 전송 후 clear() 등 외부에서 이름이 비워지면 입력칸도 따라 비운다.
    // (포커스/커서 유지 위해 값이 실제로 다를 때만 건드린다)
    final clientName = ref.watch(cartProvider.select((c) => c.clientName));
    if (_clientController.text != clientName) {
      _clientController.value = TextEditingValue(
        text: clientName,
        selection: TextSelection.collapsed(offset: clientName.length),
      );
    }

    return Column(
      children: [
        _HomeButton(
          emoji: '🔎',
          title: 'Buscar producto',
          subtitle: 'Elegir de la lista',
          onTap: () => context.push('/catalog'),
        ),
        const SizedBox(height: 12),
        // Ítem libre 진입은 Buscar producto(카탈로그) 화면 안에 있다 — 상품을 찾다
        // 없을 때가 필요한 순간이라 홈 카드로 분리하지 않는다.
        _HomeButton(
          emoji: '🛒',
          title: 'Ver carrito',
          subtitle: 'Editar y mandar a caja',
          badge: widget.cartUnits > 0 ? widget.cartUnits : null,
          onTap: () => context.push('/comanda'),
        ),
        const SizedBox(height: 12),
        // [2026-10-06] Modo lector — debajo de «Ver carrito»: leer la etiqueta y sumar con «+1»
        _HomeButton(
          emoji: '📷',
          title: 'Modo lector',
          subtitle: 'Leé la etiqueta y tocá +1 por unidad',
          onTap: () => context.push('/lector'),
        ),
        const Spacer(),
        // cliente (opcional) — QR 스캔 전에 이름부터 적는 플로우
        TextField(
          controller: _clientController,
          onChanged: (v) => ref.read(cartProvider.notifier).setClientName(v),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre del cliente (opcional)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        // QR = primary big (navy) → 스캐너 바텀시트 (D-14 scan-to-detail)
        _HomeButton(
          emoji: '▣',
          title: 'Escanear QR',
          subtitle: 'Leé la percha y probá al instante',
          primary: true,
          onTap: () => showQrScannerSheet(context),
        ),
        const SizedBox(height: 12),
        // 근무 중이라도 언제든 퇴근(salida) 가능 — 같은 fichaje 스캐너.
        TextButton.icon(
          onPressed: () => showFichajeScannerSheet(context),
          icon: const Icon(Icons.logout, size: 18, color: AppColors.muted),
          label: const Text('Fichar salida',
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// 미출근(clockedIn=false) 게이트 — "Fichá tu entrada para empezar" + fichaje 버튼만.
// 작업 액션은 잠금(greyed + 안내). 백엔드 RequireAttendanceGuard 미러링.
class _ClockInGate extends StatelessWidget {
  const _ClockInGate();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.amberSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fichá tu entrada para empezar',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Escaneá el QR de fichaje de la caja para habilitar el catálogo y las ventas.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 작업 버튼 잠금(비활성 + 안내). 스캔 전엔 백엔드도 NOT_CLOCKED_IN 으로 차단.
        const _HomeButton(
          emoji: '🔎',
          title: 'Buscar producto',
          subtitle: 'Fichá tu entrada para habilitar',
          disabled: true,
        ),
        const SizedBox(height: 12),
        const _HomeButton(
          emoji: '🛒',
          title: 'Ver carrito',
          subtitle: 'Fichá tu entrada para habilitar',
          disabled: true,
        ),
        const SizedBox(height: 12),
        const _HomeButton(
          emoji: '📷',
          title: 'Modo lector',
          subtitle: 'Fichá tu entrada para habilitar',
          disabled: true,
        ),
        const Spacer(),
        _HomeButton(
          emoji: '🕑',
          title: 'Fichar entrada/salida',
          subtitle: 'Escaneá el QR de la caja',
          primary: true,
          onTap: () => showFichajeScannerSheet(context),
        ),
      ],
    );
  }
}

class _HomeButton extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool primary;
  final bool disabled;
  final int? badge;
  final VoidCallback? onTap;

  const _HomeButton({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.onTap,
lib/features/scanner/views/lector_screen.dart:192:    final res = ref.read(cartProvider.notifier).addScanned(leido.linea);
lib/features/scanner/views/lector_screen.dart:204:      .firstWhere((l) => l.lineKey == leido.linea.lineKey, orElse: () => leido.linea.copyWith(quantity: 0))
lib/features/scanner/logic/lector_logic.dart:12:class Antirebote {
lib/features/cart/providers/cart_provider.dart:9:class CartLine {
lib/features/cart/providers/cart_provider.dart:57:  CartLine copyWith({int? quantity}) => CartLine(
lib/features/cart/providers/cart_provider.dart:86:  CartState copyWith({List<CartLine>? lines, String? clientName}) => CartState(
lib/features/cart/providers/cart_provider.dart:112:        map[incoming.lineKey] = existing.copyWith(quantity: merged);
lib/features/cart/providers/cart_provider.dart:115:    state = state.copyWith(
lib/features/cart/providers/cart_provider.dart:129:    state = state.copyWith(
lib/features/cart/providers/cart_provider.dart:141:        return l.copyWith(quantity: l.quantity + 1);
lib/features/cart/providers/cart_provider.dart:147:      state = state.copyWith(lines: lines);
lib/features/cart/providers/cart_provider.dart:160:          lines.add(l.copyWith(quantity: q));
lib/features/cart/providers/cart_provider.dart:166:    state = state.copyWith(lines: lines);
lib/features/cart/providers/cart_provider.dart:170:    state = state.copyWith(
lib/features/cart/providers/cart_provider.dart:178:  ScanAdd addScanned(CartLine line) {
lib/features/cart/providers/cart_provider.dart:185:      state = state.copyWith(lines: [...state.lines, line.copyWith(quantity: 1)]);
lib/features/cart/providers/cart_provider.dart:194:    lines[i] = actual.copyWith(quantity: actual.quantity + 1);
lib/features/cart/providers/cart_provider.dart:195:    state = state.copyWith(lines: lines);
lib/features/cart/providers/cart_provider.dart:222:    state = state.copyWith(lines: [...state.lines, line]);
lib/features/cart/providers/cart_provider.dart:225:  void setClientName(String name) => state = state.copyWith(clientName: name);
lib/features/revendedor/providers/reseller_catalog_provider.dart:41:  ResellerCatalogState copyWith({
lib/features/revendedor/providers/reseller_catalog_provider.dart:123:      state = AsyncData(current.copyWith(isLoadingMore: false, loadMoreError: e.message));
lib/features/revendedor/providers/reseller_catalog_provider.dart:125:      state = AsyncData(current.copyWith(

hook: PostToolUse
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,230p' lib/features/cart/providers/cart_provider.dart; sed -n '1,100p' lib/features/scanner/logic/lector_logic.dart; rg -n \"lector|LectorScreen|_WorkActions|ClockInGate\" lib test; nl -ba lib/features/scanner/views/lector_screen.dart | sed -n '80,225p'; nl -ba lib/features/home/views/home_screen.dart | sed -n '300,435p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/mobile-sales-app
 succeeded in 0ms:
// 카트 Provider — 변형(colorId-sizeId) 단위 라인 관리. [UI-D2] 모든 라인은 자지점,
// 라인 수량은 자지점 available 한도로만 증가(traslado/타지점 배분 없음).
// suspended 판매(POST /mobile/sales)로 보낼 때 productId 로 그룹핑해 items 로 매핑한다.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 카트 라인 = 상품 + 색상/talle 변형 1건 (S4 Comanda 라인 = 변형 단위 표시)
@immutable
class CartLine {
  // Ítem libre(código 없는 즉석 품목)는 productId 없음(null) → 백엔드가 customName 으로 저장.
  final int? productId;
  final String productName;
  final double price;
  final int? colorId;
  final String colorName;
  final int? colorHex;
  final int? sizeId;
  final String sizeName;
  final int quantity;
  // 자지점 available (라인 stepper 상한 — UI-D2). 매장이 재고 없이 판매를 허용하면
  // 사실상 무제한 값이 들어온다(자유품목도 무제한).
  final int ownAvailable;
  // 실제 자지점 재고 (표시 전용 — "→ n disp." 문구). 상한과 분리해야 무제한 cap 이
  // 그대로 화면에 찍히지 않는다.
  final int ownStock;
  // 자유품목 여부 + 고유키(같은 변형키 충돌 방지). 카탈로그 상품이면 false/null.
  final bool isFreeItem;
  final String? freeKey;

  const CartLine({
    required this.productId,
    required this.productName,
    required this.price,
    required this.colorId,
    required this.colorName,
    required this.colorHex,
    required this.sizeId,
    required this.sizeName,
    required this.quantity,
    required this.ownAvailable,
    this.ownStock = 0,
    this.isFreeItem = false,
    this.freeKey,
  });

  // 그룹핑 키 — 자유품목은 고유키, 카탈로그 상품은 colorId-sizeId(웹 계약 동일).
  // ★ 서버로 보내는 상품 안의 키(variantQuantities)다. 카트 안에서 줄을 가리킬 때는 lineKey.
  String get variantKey => isFreeItem ? freeKey! : '$colorId-$sizeId';

  // [2026-10-05] 카트 안의 줄 식별자 — 상품 id 까지 포함한다.
  // variantKey 만 쓰면 색상·사이즈가 같은 **다른 상품**이 한 줄로 취급됐다(Cielo: 변형 12개가
  // 조합 7개 — COLOR ÚNICO/Talle Única). + 를 누르면 다른 상품 줄까지 같이 늘었다.
  String get lineKey => isFreeItem ? freeKey! : '$productId:$colorId-$sizeId';

  double get subtotal => price * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        productId: productId,
        productName: productName,
        price: price,
        colorId: colorId,
        colorName: colorName,
        colorHex: colorHex,
        sizeId: sizeId,
        sizeName: sizeName,
        quantity: quantity ?? this.quantity,
        ownAvailable: ownAvailable,
        ownStock: ownStock,
        isFreeItem: isFreeItem,
        freeKey: freeKey,
      );
}

// 카트 전체 상태 (라인들 + 선택 고객명)
@immutable
class CartState {
  final List<CartLine> lines;
  final String clientName;

  const CartState({this.lines = const [], this.clientName = ''});

  int get totalUnits => lines.fold(0, (sum, l) => sum + l.quantity);
  double get subtotal => lines.fold(0.0, (sum, l) => sum + l.subtotal);
  bool get isEmpty => lines.isEmpty;

  CartState copyWith({List<CartLine>? lines, String? clientName}) => CartState(
        lines: lines ?? this.lines,
        clientName: clientName ?? this.clientName,
      );
}

// Modo lector 결과 — 담았는지, 자지점 한도에 걸렸는지
enum ScanAdd { agregado, limite }

// 카트 Notifier Provider
final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  // 매트릭스 선택 라인들을 카트에 병합 (같은 변형은 수량 합산, 자지점 상한 클램프)
  void mergeLines(List<CartLine> newLines) {
    final map = {for (final l in state.lines) l.lineKey: l};
    for (final incoming in newLines) {
      final existing = map[incoming.lineKey];
      if (existing == null) {
        map[incoming.lineKey] = incoming;
      } else {
        final merged = (existing.quantity + incoming.quantity)
            .clamp(0, incoming.ownAvailable);
        map[incoming.lineKey] = existing.copyWith(quantity: merged);
      }
    }
    state = state.copyWith(
      lines: map.values.where((l) => l.quantity > 0).toList(),
    );
  }

  // 한 상품(productId)의 라인 전체를 새 목록으로 교체.
  // 상품 상세를 "카트 편집기"로 쓰기 위한 경로 — mergeLines 처럼 합산하지 않으므로
  // 같은 상품을 다시 담아도 수량이 2배로 불어나지 않는다. newLines 가 비면 카트에서 빠진다.
  // 자유품목(isFreeItem)은 productId 가 null 이라 영향받지 않는다.
  void replaceProductLines(int productId, List<CartLine> newLines) {
    final kept = state.lines.where(
      (l) => l.isFreeItem || l.productId != productId,
    );

    state = state.copyWith(
      lines: [...kept, ...newLines.where((l) => l.quantity > 0)],
    );
  }

  // 라인 수량 증가 (자지점 available 한도 — 초과 시 false 반환 → "Sin disponible" 토스트)
  bool increment(String lineKey) {
    var changed = false;
    final lines = state.lines.map((l) {
      if (l.lineKey == lineKey && l.quantity < l.ownAvailable) {
        changed = true;

        return l.copyWith(quantity: l.quantity + 1);
      }

      return l;
    }).toList();
    if (changed) {
      state = state.copyWith(lines: lines);
    }

    return changed;
  }

  // 라인 수량 감소 (0 이면 라인 제거)
  void decrement(String lineKey) {
    final lines = <CartLine>[];
    for (final l in state.lines) {
      if (l.lineKey == lineKey) {
        final q = l.quantity - 1;
        if (q > 0) {
          lines.add(l.copyWith(quantity: q));
        }
      } else {
        lines.add(l);
      }
    }
    state = state.copyWith(lines: lines);
  }

  void removeLine(String lineKey) {
    state = state.copyWith(
      lines: state.lines.where((l) => l.lineKey != lineKey).toList(),
    );
  }

  // [2026-10-05] Modo lector — 스캔 1회 = 그 변형 +1.
  // 이미 카트에 있으면 그 줄을 +1 (자지점 한도까지), 없으면 수량 1 로 새 줄.
  // 한도에 걸리면 아무것도 바꾸지 않고 [ScanAdd.limite] — 화면이 경고한다.
  ScanAdd addScanned(CartLine line) {
    final key = line.lineKey;
    final i = state.lines.indexWhere((l) => l.lineKey == key);
    if (i < 0) {
      if (line.ownAvailable < 1) {
        return ScanAdd.limite;
      }
      state = state.copyWith(lines: [...state.lines, line.copyWith(quantity: 1)]);

      return ScanAdd.agregado;
    }
    final actual = state.lines[i];
    if (actual.quantity >= line.ownAvailable) {
      return ScanAdd.limite;
    }
    final lines = [...state.lines];
    lines[i] = actual.copyWith(quantity: actual.quantity + 1);
    state = state.copyWith(lines: lines);

    return ScanAdd.agregado;
  }

  // Ítem libre 추가 — código 없이 설명/단가/수량만. 재고 무관(ownAvailable 무제한),
  // 고유키(freeKey)로 그룹핑해 다른 자유품목과 합쳐지지 않게 한다.
  void addFreeItem({
    required String description,
    required double price,
    required int quantity,
  }) {
    final key = 'free-${DateTime.now().microsecondsSinceEpoch}';
    final line = CartLine(
      productId: null,
      productName: description,
      price: price,
      colorId: null,
      colorName: '',
      colorHex: null,
      sizeId: null,
      sizeName: '',
      quantity: quantity,
      ownAvailable: 999999,
      isFreeItem: true,
      freeKey: key,
    );
    state = state.copyWith(lines: [...state.lines, line]);
  }

  void setClientName(String name) => state = state.copyWith(clientName: name);

  void clear() => state = const CartState();
}
// [2026-10-05] Modo lector — reglas puras (testeables sin cámara ni red).
import '../../product/data/stock_dto.dart';

// Mismo tope que el detalle cuando la tienda vende sin stock (VariantMatrixController._noStockCap).
const int kSinTopeStock = 9999;

// La cámara detecta el mismo código varias veces por segundo mientras está en cuadro.
// Sin esto, una sola pasada cargaba 3–4 unidades.
// ★ Ventana DESLIZANTE: cada lectura (aceptada o no) renueva la marca. Un código que se queda
//   frente a la cámara no vuelve a sumar nunca; para sumar otra unidad hay que sacarlo del
//   cuadro ≥ 1,5 s y volver a apuntar (codex 2026-10-05: con ventana fija sumaba cada 1,5 s).
class Antirebote {
  final Duration ventana;
  final Map<String, DateTime> _ultimo = {};

  Antirebote({this.ventana = const Duration(milliseconds: 1500)});

  // true = procesar este código ahora
  bool aceptar(String code, DateTime ahora) {
    final previo = _ultimo[code];
    _ultimo[code] = ahora;

    return previo == null || ahora.difference(previo) >= ventana;
  }
}

// La variante escaneada dentro del stock de su madre (color y talle, null incluido).
// ★ Dos variantes con el mismo color/talle → null: no se sabe cuál es (no se adivina).
VariantStock? buscarVariante(List<VariantStock> variantes, int? colorId, int? sizeId) {
  final iguales = variantes.where((v) => v.color.id == colorId && v.size.id == sizeId).toList();

  return iguales.length == 1 ? iguales.single : null;
}

// Tope de unidades en el carrito — misma regla que el detalle (UI-D2):
// la tienda vende sin stock → sin tope; si no, el stock propio de la sucursal.
int topeDisponible(VariantStock v, {required bool allowSaleWithoutStock}) {
  if (allowSaleWithoutStock) {
    return kSinTopeStock;
  }

  return v.stock < 0 ? 0 : v.stock;
}
lib/router/app_router.dart:9:import '../features/scanner/views/lector_screen.dart';
lib/router/app_router.dart:28:import '../features/revendedor/views/reseller_store_selector_screen.dart';
lib/router/app_router.dart:170:      // [2026-10-05] Modo lector — escanear y sumar al carrito
lib/router/app_router.dart:172:        path: '/lector',
lib/router/app_router.dart:173:        builder: (context, state) => LectorScreen(
lib/router/app_router.dart:223:        builder: (context, state) => const ResellerStoreSelectorScreen(),
test/lector_test.dart:1:// [2026-10-05] Modo lector + clave de línea del carrito.
test/lector_test.dart:6:import 'package:mobile_sales_app/features/scanner/logic/lector_logic.dart';
lib/features/scanner/views/lector_screen.dart:1:// [2026-10-05] Modo lector — la cámara queda abierta y muestra el producto leído.
lib/features/scanner/views/lector_screen.dart:22:import '../logic/lector_logic.dart';
lib/features/scanner/views/lector_screen.dart:36:class LectorScreen extends ConsumerStatefulWidget {
lib/features/scanner/views/lector_screen.dart:40:  const LectorScreen({super.key, this.desdeCarrito = false});
lib/features/scanner/views/lector_screen.dart:43:  ConsumerState<LectorScreen> createState() => _LectorScreenState();
lib/features/scanner/views/lector_screen.dart:56:class _LectorScreenState extends ConsumerState<LectorScreen> {
lib/features/scanner/views/lector_screen.dart:229:        title: const Text('Modo lector', style: TextStyle(fontSize: 17)),
test/reseller_login_screen_test.dart:45:// (reseller_store_selector_test.dart 와 동일 패턴).
test/reseller_store_selector_test.dart:1:// ResellerStoreSelectorScreen 위젯 테스트 — 매장 리스트 렌더 + 선택 시 provider 갱신,
test/reseller_store_selector_test.dart:12:import 'package:mobile_sales_app/features/revendedor/views/reseller_store_selector_screen.dart';
test/reseller_store_selector_test.dart:33:          builder: (context, state) => const ResellerStoreSelectorScreen(),
lib/features/scanner/data/scan_repository.dart:1:// [2026-10-05] Modo lector — GET /mobile/scan/:code
lib/features/scanner/logic/lector_logic.dart:1:// [2026-10-05] Modo lector — reglas puras (testeables sin cámara ni red).
lib/features/auth/widgets/sucursal_selector.dart:6:class SucursalSelector extends StatelessWidget {
lib/features/auth/widgets/sucursal_selector.dart:19:  const SucursalSelector({
lib/features/auth/views/login_screen.dart:10:import '../widgets/sucursal_selector.dart';
lib/features/auth/views/login_screen.dart:217:                  SucursalSelector(
lib/features/cart/views/comanda_screen.dart:83:          // [2026-10-05] Modo lector — seguir escaneando desde el carrito
lib/features/cart/views/comanda_screen.dart:85:            tooltip: 'Modo lector',
lib/features/cart/views/comanda_screen.dart:86:            onPressed: () => context.push('/lector?desde=carrito'),
lib/features/auth/views/branch_selection_screen.dart:10:import '../widgets/sucursal_selector.dart';
lib/features/auth/views/branch_selection_screen.dart:134:                SucursalSelector(
lib/features/cart/providers/cart_provider.dart:92:// Modo lector 결과 — 담았는지, 자지점 한도에 걸렸는지
lib/features/cart/providers/cart_provider.dart:175:  // [2026-10-05] Modo lector — 스캔 1회 = 그 변형 +1.
lib/features/revendedor/views/store_selector_screen.dart:1:// Modo Revendedor — Store selector STUB (BLOCKED, D-07).
lib/features/revendedor/views/store_selector_screen.dart:12:class StoreSelectorScreen extends ConsumerWidget {
lib/features/revendedor/views/store_selector_screen.dart:13:  const StoreSelectorScreen({super.key});
lib/features/revendedor/views/store_selector_screen.dart:46:// Ventago 테마 자리표시자 (store_selector / quote 공용 룩).
lib/features/home/views/home_screen.dart:1:// S1 Home (/home) — vendedor 랜딩. 4버튼(Buscar / Ver carrito / Modo lector / Escanear QR).
lib/features/home/views/home_screen.dart:159:                    ? _WorkActions(cartUnits: cartUnits)
lib/features/home/views/home_screen.dart:160:                    : const _ClockInGate(),
lib/features/home/views/home_screen.dart:272:class _WorkActions extends ConsumerStatefulWidget {
lib/features/home/views/home_screen.dart:275:  const _WorkActions({required this.cartUnits});
lib/features/home/views/home_screen.dart:278:  ConsumerState<_WorkActions> createState() => _WorkActionsState();
lib/features/home/views/home_screen.dart:281:class _WorkActionsState extends ConsumerState<_WorkActions> {
lib/features/home/views/home_screen.dart:327:        // [2026-10-06] Modo lector — debajo de «Ver carrito»: leer la etiqueta y sumar con «+1»
lib/features/home/views/home_screen.dart:330:          title: 'Modo lector',
lib/features/home/views/home_screen.dart:332:          onTap: () => context.push('/lector'),
lib/features/home/views/home_screen.dart:369:class _ClockInGate extends StatelessWidget {
lib/features/home/views/home_screen.dart:370:  const _ClockInGate();
lib/features/home/views/home_screen.dart:420:          title: 'Modo lector',
lib/features/revendedor/views/reseller_store_selector_screen.dart:4:// `views/store_selector_screen.dart`(구 MultiStoreScope 스텁, Phase 24 게이트로 BLOCKED,
lib/features/revendedor/views/reseller_store_selector_screen.dart:20:class ResellerStoreSelectorScreen extends ConsumerWidget {
lib/features/revendedor/views/reseller_store_selector_screen.dart:21:  const ResellerStoreSelectorScreen({super.key});
lib/features/revendedor/views/reseller_home_screen.dart:131:// 보여주고, 탭하면 /revendedor/tiendas(ResellerStoreSelectorScreen)로 이동해 바꿀 수 있다.
lib/features/catalog/views/catalog_screen.dart:57:          // [2026-10-05] Modo lector — escanear etiquetas y sumarlas al carrito
lib/features/catalog/views/catalog_screen.dart:59:            onPressed: () => context.push('/lector'),
lib/features/catalog/views/catalog_screen.dart:61:            label: const Text('Modo lector', style: TextStyle(fontSize: 13)),
lib/features/revendedor/README.md:48:- [ ] **Frontend — Store selector**: reemplazar el stub por el selector real de las N tiendas
lib/features/revendedor/README.md:73:- `views/store_selector_screen.dart` — placeholder "Próximamente — requiere Phase 24".
    80	    if (!mounted) {
    81	      return;
    82	    }
    83	    setState(() => _aviso = a);
    84	    if (a.tono == _Tono.ok) {
    85	      SystemSound.play(SystemSoundType.click);
    86	      HapticFeedback.mediumImpact();
    87	    } else {
    88	      HapticFeedback.heavyImpact();
    89	    }
    90	  }
    91	
    92	  Future<void> _onDetect(BarcodeCapture capture) async {
    93	    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    94	    final code = raw?.trim() ?? '';
    95	    if (code.isEmpty || _ocupado || !_antirebote.aceptar(code, DateTime.now())) {
    96	      return;
    97	    }
    98	    // el mismo producto sigue en cuadro: ya está elegido, no hay nada que resolver
    99	    if (code == _leido?.code) {
   100	      return;
   101	    }
   102	    _ocupado = true;
   103	    try {
   104	      await _procesar(code);
   105	    } finally {
   106	      _ocupado = false;
   107	    }
   108	  }
   109	
   110	  Future<void> _procesar(String code) async {
   111	    // QR de la percha (deeplink a la madre) — no dice color/talle
   112	    final madreQr = parseStockDeeplink(code);
   113	    if (madreQr != null) {
   114	      _mostrar(_Aviso('Código de percha: elegí color y talle', _Tono.aviso, abrirProductId: madreQr));
   115	
   116	      return;
   117	    }
   118	
   119	    final ScanResult r;
   120	    try {
   121	      r = await ref.read(scanRepositoryProvider).resolve(code);
   122	    } on ApiException catch (e) {
   123	      _mostrar(_Aviso(
   124	        switch (e.code) {
   125	          'SCAN_NOT_FOUND' => 'Código no encontrado: $code',
   126	          'SCAN_AMBIGUOUS' => 'Hay más de un producto con el código $code — cargalo desde el catálogo',
   127	          _ => e.message,
   128	        },
   129	        _Tono.error,
   130	      ));
   131	
   132	      return;
   133	    }
   134	
   135	    // ★ sin precio no se agrega: entraría como línea gratis
   136	    if (r.price <= 0) {
   137	      _mostrar(_Aviso('${r.name}: sin precio cargado — abrilo para revisarlo', _Tono.aviso, abrirProductId: r.productId));
   138	
   139	      return;
   140	    }
   141	
   142	    if (r.necesitaVariante) {
   143	      _mostrar(_Aviso('${r.name}: elegí color y talle', _Tono.aviso, abrirProductId: r.productId));
   144	
   145	      return;
   146	    }
   147	
   148	    StockResult? stock;
   149	    try {
   150	      stock = await ref.read(stockRepositoryProvider).getStock(r.productId);
   151	    } on ApiException catch (e) {
   152	      _mostrar(_Aviso(e.message, _Tono.error));
   153	
   154	      return;
   155	    }
   156	    final v = buscarVariante(stock.stockByVariant, r.colorId, r.sizeId);
   157	    if (v == null) {
   158	      // producto sin variantes, o variante que no aparece en el stock: el detalle lo resuelve
   159	      _mostrar(_Aviso('${r.name}: abrilo para cargarlo', _Tono.aviso, abrirProductId: r.productId));
   160	
   161	      return;
   162	    }
   163	
   164	    final tope = topeDisponible(v, allowSaleWithoutStock: _allowSaleWithoutStock);
   165	    final linea = CartLine(
   166	      productId: r.productId,
   167	      productName: r.name,
   168	      price: r.price,
   169	      colorId: v.color.id,
   170	      colorName: v.color.name ?? '—',
   171	      colorHex: null,
   172	      sizeId: v.size.id,
   173	      sizeName: v.size.name ?? '—',
   174	      quantity: 1,
   175	      ownAvailable: tope,
   176	      ownStock: v.stock,
   177	    );
   178	    final etiqueta = '${r.name} · ${linea.colorName} / ${linea.sizeName}';
   179	    setState(() {
   180	      _leido = _Leido(code, linea, etiqueta, v.stock);
   181	      _aviso = null;
   182	    });
   183	    HapticFeedback.selectionClick();
   184	  }
   185	
   186	  // «+1» — una unidad por toque
   187	  void _sumar() {
   188	    final leido = _leido;
   189	    if (leido == null) {
   190	      return;
   191	    }
   192	    final res = ref.read(cartProvider.notifier).addScanned(leido.linea);
   193	    if (res == ScanAdd.limite) {
   194	      _mostrar(_Aviso('Sin disponible: ${leido.etiqueta} (stock ${leido.stock})', _Tono.error));
   195	
   196	      return;
   197	    }
   198	    _mostrar(_Aviso('✓ ${leido.etiqueta} · +1 (${_enCarrito(leido)})', _Tono.ok));
   199	  }
   200	
   201	  int _enCarrito(_Leido leido) => ref
   202	      .read(cartProvider)
   203	      .lines
   204	      .firstWhere((l) => l.lineKey == leido.linea.lineKey, orElse: () => leido.linea.copyWith(quantity: 0))
   205	      .quantity;
   206	
   207	  void _verCarrito() {
   208	    if (widget.desdeCarrito) {
   209	      context.pop();
   210	    } else {
   211	      context.pushReplacement('/comanda');
   212	    }
   213	  }
   214	
   215	  @override
   216	  Widget build(BuildContext context) {
   217	    final cart = ref.watch(cartProvider);
   218	    final aviso = _aviso;
   219	
   220	    return Scaffold(
   221	      backgroundColor: Colors.black,
   222	      appBar: AppBar(
   223	        backgroundColor: AppColors.navy,
   224	        foregroundColor: Colors.white,
   225	        leading: IconButton(
   300	    final clientName = ref.watch(cartProvider.select((c) => c.clientName));
   301	    if (_clientController.text != clientName) {
   302	      _clientController.value = TextEditingValue(
   303	        text: clientName,
   304	        selection: TextSelection.collapsed(offset: clientName.length),
   305	      );
   306	    }
   307	
   308	    return Column(
   309	      children: [
   310	        _HomeButton(
   311	          emoji: '🔎',
   312	          title: 'Buscar producto',
   313	          subtitle: 'Elegir de la lista',
   314	          onTap: () => context.push('/catalog'),
   315	        ),
   316	        const SizedBox(height: 12),
   317	        // Ítem libre 진입은 Buscar producto(카탈로그) 화면 안에 있다 — 상품을 찾다
   318	        // 없을 때가 필요한 순간이라 홈 카드로 분리하지 않는다.
   319	        _HomeButton(
   320	          emoji: '🛒',
   321	          title: 'Ver carrito',
   322	          subtitle: 'Editar y mandar a caja',
   323	          badge: widget.cartUnits > 0 ? widget.cartUnits : null,
   324	          onTap: () => context.push('/comanda'),
   325	        ),
   326	        const SizedBox(height: 12),
   327	        // [2026-10-06] Modo lector — debajo de «Ver carrito»: leer la etiqueta y sumar con «+1»
   328	        _HomeButton(
   329	          emoji: '📷',
   330	          title: 'Modo lector',
   331	          subtitle: 'Leé la etiqueta y tocá +1 por unidad',
   332	          onTap: () => context.push('/lector'),
   333	        ),
   334	        const Spacer(),
   335	        // cliente (opcional) — QR 스캔 전에 이름부터 적는 플로우
   336	        TextField(
   337	          controller: _clientController,
   338	          onChanged: (v) => ref.read(cartProvider.notifier).setClientName(v),
   339	          textCapitalization: TextCapitalization.words,
   340	          decoration: const InputDecoration(
   341	            labelText: 'Nombre del cliente (opcional)',
   342	            isDense: true,
   343	          ),
   344	        ),
   345	        const SizedBox(height: 12),
   346	        // QR = primary big (navy) → 스캐너 바텀시트 (D-14 scan-to-detail)
   347	        _HomeButton(
   348	          emoji: '▣',
   349	          title: 'Escanear QR',
   350	          subtitle: 'Leé la percha y probá al instante',
   351	          primary: true,
   352	          onTap: () => showQrScannerSheet(context),
   353	        ),
   354	        const SizedBox(height: 12),
   355	        // 근무 중이라도 언제든 퇴근(salida) 가능 — 같은 fichaje 스캐너.
   356	        TextButton.icon(
   357	          onPressed: () => showFichajeScannerSheet(context),
   358	          icon: const Icon(Icons.logout, size: 18, color: AppColors.muted),
   359	          label: const Text('Fichar salida',
   360	              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
   361	        ),
   362	      ],
   363	    );
   364	  }
   365	}
   366	
   367	// 미출근(clockedIn=false) 게이트 — "Fichá tu entrada para empezar" + fichaje 버튼만.
   368	// 작업 액션은 잠금(greyed + 안내). 백엔드 RequireAttendanceGuard 미러링.
   369	class _ClockInGate extends StatelessWidget {
   370	  const _ClockInGate();
   371	
   372	  @override
   373	  Widget build(BuildContext context) {
   374	    return Column(
   375	      children: [
   376	        Container(
   377	          width: double.infinity,
   378	          padding: const EdgeInsets.all(20),
   379	          decoration: BoxDecoration(
   380	            color: AppColors.amberSoft,
   381	            borderRadius: BorderRadius.circular(18),
   382	          ),
   383	          child: const Column(
   384	            crossAxisAlignment: CrossAxisAlignment.start,
   385	            children: [
   386	              Text(
   387	                'Fichá tu entrada para empezar',
   388	                style: TextStyle(
   389	                  color: AppColors.ink,
   390	                  fontSize: 18,
   391	                  fontWeight: FontWeight.w800,
   392	                ),
   393	              ),
   394	              SizedBox(height: 6),
   395	              Text(
   396	                'Escaneá el QR de fichaje de la caja para habilitar el catálogo y las ventas.',
   397	                style: TextStyle(color: AppColors.muted, fontSize: 13),
   398	              ),
   399	            ],
   400	          ),
   401	        ),
   402	        const SizedBox(height: 16),
   403	        // 작업 버튼 잠금(비활성 + 안내). 스캔 전엔 백엔드도 NOT_CLOCKED_IN 으로 차단.
   404	        const _HomeButton(
   405	          emoji: '🔎',
   406	          title: 'Buscar producto',
   407	          subtitle: 'Fichá tu entrada para habilitar',
   408	          disabled: true,
   409	        ),
   410	        const SizedBox(height: 12),
   411	        const _HomeButton(
   412	          emoji: '🛒',
   413	          title: 'Ver carrito',
   414	          subtitle: 'Fichá tu entrada para habilitar',
   415	          disabled: true,
   416	        ),
   417	        const SizedBox(height: 12),
   418	        const _HomeButton(
   419	          emoji: '📷',
   420	          title: 'Modo lector',
   421	          subtitle: 'Fichá tu entrada para habilitar',
   422	          disabled: true,
   423	        ),
   424	        const Spacer(),
   425	        _HomeButton(
   426	          emoji: '🕑',
   427	          title: 'Fichar entrada/salida',
   428	          subtitle: 'Escaneá el QR de la caja',
   429	          primary: true,
   430	          onTap: () => showFichajeScannerSheet(context),
   431	        ),
   432	      ],
   433	    );
   434	  }
   435	}

hook: PostToolUse
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse Completed
exec
/bin/zsh -lc "nl -ba lib/features/home/views/home_screen.dart | sed -n '100,180p'; nl -ba lib/router/app_router.dart | sed -n '160,180p'; sed -n '1,180p' test/lector_test.dart; rg -n \"HomeScreen|home_screen|ClockIn\" test" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/mobile-sales-app
 succeeded in 0ms:
   100	                        value: 'logout',
   101	                        child: ListTile(
   102	                          contentPadding: EdgeInsets.zero,
   103	                          leading: Icon(Icons.logout, color: Color(0xFFB9B9C6)),
   104	                          title: Text('Salir', style: TextStyle(color: Colors.white)),
   105	                        ),
   106	                      ),
   107	                    ],
   108	                    // 기존 아바타 그대로 — 모양 변경 없음, 탭 동작만 추가
   109	                    child: CircleAvatar(
   110	                      radius: 24,
   111	                      backgroundColor: AppColors.gold,
   112	                      child: Text(
   113	                        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
   114	                        style: const TextStyle(
   115	                          color: AppColors.navy2,
   116	                          fontWeight: FontWeight.w800,
   117	                          fontSize: 18,
   118	                        ),
   119	                      ),
   120	                    ),
   121	                  ),
   122	                  const SizedBox(width: 14),
   123	                  Expanded(
   124	                    child: Column(
   125	                      crossAxisAlignment: CrossAxisAlignment.start,
   126	                      children: [
   127	                        Text(
   128	                          'Hola, $name',
   129	                          style: const TextStyle(
   130	                            color: Colors.white,
   131	                            fontSize: 18,
   132	                            fontWeight: FontWeight.w700,
   133	                          ),
   134	                        ),
   135	                        const SizedBox(height: 2),
   136	                        Text(
   137	                          '📍 $store · Sucursal $branch',
   138	                          style: const TextStyle(color: Color(0xFFB9B9C6), fontSize: 12),
   139	                        ),
   140	                        const SizedBox(height: 2),
   141	                        // 컴파일 날짜(버전 식별) — 빌드 시 --dart-define=BUILD_DATE 주입
   142	                        Text(
   143	                          'build ${BuildInfo.date}',
   144	                          style: const TextStyle(color: Color(0xFF6B6B7B), fontSize: 10),
   145	                        ),
   146	                      ],
   147	                    ),
   148	                  ),
   149	                ],
   150	              ),
   151	            ),
   152	            // 이번 달 본인 근무시간 요약
   153	            const _MonthHoursCard(),
   154	            // 본문 — 출근 여부로 분기
   155	            Expanded(
   156	              child: Padding(
   157	                padding: const EdgeInsets.all(16),
   158	                child: clockedIn
   159	                    ? _WorkActions(cartUnits: cartUnits)
   160	                    : const _ClockInGate(),
   161	              ),
   162	            ),
   163	          ],
   164	        ),
   165	      ),
   166	    );
   167	  }
   168	
   169	  // 근무 지점 변경 — 매장 활성 지점 중 선택 → setBranchScope 재호출로 세션 scope 교체.
   170	  // '근무 지점이 정해지지 않은' 다지점 판매원이 로그인 후 언제든 바꿀 수 있게 한다.
   171	  Future<void> _showBranchSwitcher(
   172	    BuildContext context,
   173	    WidgetRef ref,
   174	    List<BranchOption> options,
   175	    String? currentBranchName,
   176	  ) async {
   177	    final selected = await showModalBottomSheet<int>(
   178	      context: context,
   179	      backgroundColor: AppColors.navy2,
   180	      shape: const RoundedRectangleBorder(
   160	          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
   161	          // 카탈로그에서 넘어온 CatalogItem(hero/price). QR 직행 시 null → 캐시 역참조.
   162	          final extra = state.extra;
   163	
   164	          return ProductDetailScreen(
   165	            productId: id,
   166	            item: extra is CatalogItem ? extra : null,
   167	          );
   168	        },
   169	      ),
   170	      // [2026-10-05] Modo lector — escanear y sumar al carrito
   171	      GoRoute(
   172	        path: '/lector',
   173	        builder: (context, state) => LectorScreen(
   174	          desdeCarrito: state.uri.queryParameters['desde'] == 'carrito',
   175	        ),
   176	      ),
   177	      GoRoute(
   178	        path: '/comanda',
   179	        builder: (context, state) => const ComandaScreen(),
   180	      ),
// [2026-10-05] Modo lector + clave de línea del carrito.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sales_app/features/cart/providers/cart_provider.dart';
import 'package:mobile_sales_app/features/product/data/stock_dto.dart';
import 'package:mobile_sales_app/features/scanner/logic/lector_logic.dart';

CartLine linea({required int productId, int? colorId = 3, int? sizeId = 9, int tope = 5}) => CartLine(
      productId: productId,
      productName: 'P$productId',
      price: 100,
      colorId: colorId,
      colorName: 'ÚNICO',
      colorHex: null,
      sizeId: sizeId,
      sizeName: 'Única',
      quantity: 1,
      ownAvailable: tope,
    );

VariantStock vs(int? c, int? s, int stock) => VariantStock(
      color: VariantLabel(id: c, name: 'c$c'),
      size: VariantLabel(id: s, name: 's$s'),
      stock: stock,
      stockByBranch: const {},
    );

void main() {
  group('Antirebote', () {
    test('el mismo código dentro de 1,5 s se ignora; tras 1,5 s sin verlo vuelve a contar', () {
      final a = Antirebote();
      final t0 = DateTime(2026, 10, 5, 12);

      expect(a.aceptar('X', t0), isTrue);
      expect(a.aceptar('X', t0.add(const Duration(milliseconds: 600))), isFalse);
      // 1,5 s después de la ÚLTIMA lectura (600 ms) → 2100 ms
      expect(a.aceptar('X', t0.add(const Duration(milliseconds: 2100))), isTrue);
    });

    test('★ código que se queda frente a la cámara no vuelve a sumar', () {
      final a = Antirebote();
      final t0 = DateTime(2026, 10, 5, 12);

      expect(a.aceptar('X', t0), isTrue);
      // la cámara lo sigue leyendo cada 300 ms durante 6 s
      var sumas = 0;
      for (var ms = 300; ms <= 6000; ms += 300) {
        if (a.aceptar('X', t0.add(Duration(milliseconds: ms)))) sumas++;
      }
      expect(sumas, 0);
    });

    test('control: otro código no espera', () {
      final a = Antirebote();
      final t0 = DateTime(2026, 10, 5, 12);

      expect(a.aceptar('X', t0), isTrue);
      expect(a.aceptar('Y', t0.add(const Duration(milliseconds: 100))), isTrue);
    });
  });

  group('buscarVariante / topeDisponible', () {
    test('encuentra por color y talle exactos', () {
      final v = buscarVariante([vs(1, 2, 4), vs(3, 9, 7)], 3, 9);

      expect(v?.stock, 7);
    });

    test('no confunde talle', () {
      expect(buscarVariante([vs(3, 8, 4)], 3, 9), isNull);
    });

    test('★ dos variantes con el mismo color/talle → no adivina', () {
      expect(buscarVariante([vs(3, 9, 4), vs(3, 9, 6)], 3, 9), isNull);
    });

    test('tienda que vende sin stock → sin tope; si no, el stock (negativo = 0)', () {
      expect(topeDisponible(vs(1, 1, 2), allowSaleWithoutStock: true), kSinTopeStock);
      expect(topeDisponible(vs(1, 1, 2), allowSaleWithoutStock: false), 2);
      expect(topeDisponible(vs(1, 1, -3), allowSaleWithoutStock: false), 0);
    });
  });

  group('carrito — addScanned y lineKey', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('primera lectura agrega 1, la segunda suma 1 a la misma línea', () {
      final n = c.read(cartProvider.notifier);

      expect(n.addScanned(linea(productId: 743)), ScanAdd.agregado);
      expect(n.addScanned(linea(productId: 743)), ScanAdd.agregado);
      expect(c.read(cartProvider).lines, hasLength(1));
      expect(c.read(cartProvider).lines.single.quantity, 2);
    });

    test('★ tope: no pasa del disponible y avisa', () {
      final n = c.read(cartProvider.notifier);

      expect(n.addScanned(linea(productId: 743, tope: 1)), ScanAdd.agregado);
      expect(n.addScanned(linea(productId: 743, tope: 1)), ScanAdd.limite);
      expect(c.read(cartProvider).lines.single.quantity, 1);
    });

    test('sin stock (tope 0) → no agrega ninguna línea', () {
      expect(c.read(cartProvider.notifier).addScanned(linea(productId: 743, tope: 0)), ScanAdd.limite);
      expect(c.read(cartProvider).lines, isEmpty);
    });

    test('★ dos productos con el mismo color/talle son líneas distintas (caso Cielo)', () {
      final n = c.read(cartProvider.notifier);
      n.addScanned(linea(productId: 743));
      n.addScanned(linea(productId: 744));

      expect(c.read(cartProvider).lines, hasLength(2));

      // + en una línea no toca a la otra
      n.increment(linea(productId: 743).lineKey);
      final q = {for (final l in c.read(cartProvider).lines) l.productId: l.quantity};
      expect(q, {743: 2, 744: 1});

      n.decrement(linea(productId: 744).lineKey);
      expect(c.read(cartProvider).lines.map((l) => l.productId), [743]);
    });

    test('control: la clave que va al servidor sigue siendo color-talle', () {
      expect(linea(productId: 743).variantKey, '3-9');
    });
  });
}
test/reseller_home_recommendations_test.dart:1:// ResellerHomeScreen 위젯 테스트 — 추천 리스트 렌더(데이터/빈 상태) (Task 4.1).
test/reseller_home_recommendations_test.dart:12:import 'package:mobile_sales_app/features/revendedor/views/reseller_home_screen.dart';
test/reseller_home_recommendations_test.dart:40:    child: const MaterialApp(home: ResellerHomeScreen()),

hook: PostToolUse
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse Completed
exec
/bin/zsh -lc "nl -ba lib/features/home/views/home_screen.dart | sed -n '435,530p'; nl -ba lib/features/home/views/home_screen.dart | sed -n '15,100p'; rg -n \"class _MonthHoursCard\" lib/features/home/views/home_screen.dart" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/mobile-sales-app
 succeeded in 0ms:
   435	}
   436	
   437	class _HomeButton extends StatelessWidget {
   438	  final String emoji;
   439	  final String title;
   440	  final String subtitle;
   441	  final bool primary;
   442	  final bool disabled;
   443	  final int? badge;
   444	  final VoidCallback? onTap;
   445	
   446	  const _HomeButton({
   447	    required this.emoji,
   448	    required this.title,
   449	    required this.subtitle,
   450	    this.onTap,
   451	    this.primary = false,
   452	    this.disabled = false,
   453	    this.badge,
   454	  });
   455	
   456	  @override
   457	  Widget build(BuildContext context) {
   458	    final bg = primary ? AppColors.navy : AppColors.soft;
   459	    final titleColor = primary ? Colors.white : AppColors.ink;
   460	    final subColor = primary ? const Color(0xFFB9B9C6) : AppColors.muted;
   461	
   462	    final button = SizedBox(
   463	      width: double.infinity,
   464	      child: Material(
   465	        color: bg,
   466	        borderRadius: BorderRadius.circular(18),
   467	        child: InkWell(
   468	          borderRadius: BorderRadius.circular(18),
   469	          onTap: disabled ? null : onTap,
   470	          child: Padding(
   471	            padding: EdgeInsets.symmetric(horizontal: 18, vertical: primary ? 26 : 20),
   472	            child: Row(
   473	              children: [
   474	                Text(emoji, style: const TextStyle(fontSize: 28)),
   475	                const SizedBox(width: 16),
   476	                Expanded(
   477	                  child: Column(
   478	                    crossAxisAlignment: CrossAxisAlignment.start,
   479	                    children: [
   480	                      Text(
   481	                        title,
   482	                        style: TextStyle(
   483	                          color: titleColor,
   484	                          fontSize: 17,
   485	                          fontWeight: FontWeight.w700,
   486	                        ),
   487	                      ),
   488	                      const SizedBox(height: 3),
   489	                      Text(subtitle, style: TextStyle(color: subColor, fontSize: 12)),
   490	                    ],
   491	                  ),
   492	                ),
   493	                // 카트 수량 badge (0 이면 숨김)
   494	                if (badge != null)
   495	                  Container(
   496	                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
   497	                    decoration: BoxDecoration(
   498	                      color: AppColors.gold,
   499	                      borderRadius: BorderRadius.circular(20),
   500	                    ),
   501	                    child: Text(
   502	                      '$badge',
   503	                      style: const TextStyle(
   504	                        color: AppColors.navy2,
   505	                        fontWeight: FontWeight.w800,
   506	                        fontSize: 13,
   507	                        fontFeatures: kTabularFigures,
   508	                      ),
   509	                    ),
   510	                  ),
   511	              ],
   512	            ),
   513	          ),
   514	        ),
   515	      ),
   516	    );
   517	
   518	    // 잠금 상태는 흐리게 표시(작업 게이트 UX).
   519	    return disabled ? Opacity(opacity: 0.45, child: button) : button;
   520	  }
   521	}
    15	import '../../scanner/views/qr_scanner_sheet.dart';
    16	
    17	class HomeScreen extends ConsumerWidget {
    18	  const HomeScreen({super.key});
    19	
    20	  @override
    21	  Widget build(BuildContext context, WidgetRef ref) {
    22	    final scope = ref.watch(scopeNotifierProvider).value;
    23	    final cartUnits = ref.watch(cartProvider).totalUnits;
    24	    final user = switch (scope) {
    25	      BranchScope(:final user) => user,
    26	      MultiStoreScope(:final user) => user,
    27	      _ => null,
    28	    };
    29	    final name = (user?.fullName.trim().isNotEmpty ?? false)
    30	        ? user!.fullName
    31	        : 'Vendedor';
    32	    final store = user?.storeName ?? '';
    33	    final branch = user?.branchName ?? '';
    34	    // 근무 지점 미정 판매원만 상시 지점 변경 가능(백엔드 canSwitchBranch 가 권위).
    35	    final branchOptions = user?.availableBranches ?? const <BranchOption>[];
    36	    final canSwitchBranch = (user?.canSwitchBranch ?? false) && branchOptions.length >= 2;
    37	    // 출근 게이트: 열린 세션 없으면(clockedIn=false) 작업 잠금 + fichaje 유도.
    38	    final clockedIn = user?.clockedIn ?? false;
    39	
    40	    return Scaffold(
    41	      backgroundColor: AppColors.bg,
    42	      body: SafeArea(
    43	        child: Column(
    44	          children: [
    45	            // navy hello 헤더
    46	            Container(
    47	              width: double.infinity,
    48	              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    49	              color: AppColors.navy,
    50	              child: Row(
    51	                children: [
    52	                  PopupMenuButton<String>(
    53	                    tooltip: 'Menú',
    54	                    color: AppColors.navy2,
    55	                    onSelected: (value) {
    56	                      switch (value) {
    57	                        case 'branch':
    58	                          _showBranchSwitcher(context, ref, branchOptions, user?.branchName);
    59	                          break;
    60	                        case 'hours':
    61	                          context.push('/mis-horas');
    62	                          break;
    63	                        case 'adelanto':
    64	                          context.push('/adelanto');
    65	                          break;
    66	                        case 'logout':
    67	                          ref.read(scopeNotifierProvider.notifier).logout();
    68	                          break;
    69	                      }
    70	                    },
    71	                    itemBuilder: (context) => [
    72	                      if (canSwitchBranch)
    73	                        const PopupMenuItem(
    74	                          value: 'branch',
    75	                          child: ListTile(
    76	                            contentPadding: EdgeInsets.zero,
    77	                            leading: Icon(Icons.store_mall_directory_outlined,
    78	                                color: AppColors.gold),
    79	                            title: Text('Cambiar sucursal',
    80	                                style: TextStyle(color: Colors.white)),
    81	                          ),
    82	                        ),
    83	                      const PopupMenuItem(
    84	                        value: 'hours',
    85	                        child: ListTile(
    86	                          contentPadding: EdgeInsets.zero,
    87	                          leading: Icon(Icons.schedule, color: AppColors.gold),
    88	                          title: Text('Mis horas', style: TextStyle(color: Colors.white)),
    89	                        ),
    90	                      ),
    91	                      const PopupMenuItem(
    92	                        value: 'adelanto',
    93	                        child: ListTile(
    94	                          contentPadding: EdgeInsets.zero,
    95	                          leading: Icon(Icons.payments_outlined, color: AppColors.gold),
    96	                          title: Text('Adelanto', style: TextStyle(color: Colors.white)),
    97	                        ),
    98	                      ),
    99	                      const PopupMenuItem(
   100	                        value: 'logout',
227:class _MonthHoursCard extends ConsumerWidget {

hook: PostToolUse
hook: PostToolUse Completed
codex
Encontré 3 bugs concretos:

- **Alta — `lector_screen.dart:110-181`**: al escanear un código inválido después de uno válido, `_leido` no se limpia. La pantalla muestra el error, pero conserva la tarjeta y el «+1» del producto anterior; el vendedor puede sumar el artículo equivocado. **Arreglo:** limpiar `_leido` al comenzar a procesar un código diferente o en todas las salidas con error.

- **Media — `lector_screen.dart:179`**: `_procesar()` ejecuta `setState` después de varias llamadas async sin comprobar `mounted`. Si el usuario cierra la pantalla mientras se resuelve producto/stock, puede ocurrir `setState() called after dispose`. **Arreglo:** comprobar `if (!mounted) return;` después de cada `await`, especialmente antes del `setState`.

- **Media — `home_screen.dart:308-363` y `374-433`**: se agregó otro botón alto dentro de `Column` no desplazables. En equipos bajos, texto ampliado o al abrir el teclado del cliente, aparece `RenderFlex overflow` y quedan acciones inferiores inaccesibles. **Arreglo:** envolver el contenido en `SingleChildScrollView`/`ListView` y evitar depender de `Spacer` en una columna desplazable.
hook: Stop
hook: Stop Completed
tokens used
22,929
Encontré 3 bugs concretos:

- **Alta — `lector_screen.dart:110-181`**: al escanear un código inválido después de uno válido, `_leido` no se limpia. La pantalla muestra el error, pero conserva la tarjeta y el «+1» del producto anterior; el vendedor puede sumar el artículo equivocado. **Arreglo:** limpiar `_leido` al comenzar a procesar un código diferente o en todas las salidas con error.

- **Media — `lector_screen.dart:179`**: `_procesar()` ejecuta `setState` después de varias llamadas async sin comprobar `mounted`. Si el usuario cierra la pantalla mientras se resuelve producto/stock, puede ocurrir `setState() called after dispose`. **Arreglo:** comprobar `if (!mounted) return;` después de cada `await`, especialmente antes del `setState`.

- **Media — `home_screen.dart:308-363` y `374-433`**: se agregó otro botón alto dentro de `Column` no desplazables. En equipos bajos, texto ampliado o al abrir el teclado del cliente, aparece `RenderFlex overflow` y quedan acciones inferiores inaccesibles. **Arreglo:** envolver el contenido en `SingleChildScrollView`/`ListView` y evitar depender de `Spacer` en una columna desplazable.
