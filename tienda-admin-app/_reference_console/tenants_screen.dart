import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';
import 'store_message_sheet.dart';
import 'store_detail_screen.dart';
import 'borrados_screen.dart';

// Clientes(매장) 탭 — "오늘/이번 달 사용 상태" 중심 대시보드.
class TenantsScreen extends ConsumerStatefulWidget {
  const TenantsScreen({super.key});

  @override
  ConsumerState<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends ConsumerState<TenantsScreen> {
  bool _mes = false; // false=Hoy, true=Este mes
  bool _masked = false; // 금액 가림(눈 아이콘)

  @override
  void initState() {
    super.initState();
    // 탭 진입 시 최신 데이터(그날 판매순 정렬 포함)로 강제 갱신 — 캐시된 옛 순서 방지
    Future.microtask(() => ref.invalidate(tenantsProvider));
  }

  final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);

  String _fee(num n) => _masked ? r'$ ••••' : _money.format(n);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tenantsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
      data: (rows) {
        final totalFee = rows.fold<num>(0, (a, t) => a + t.expectedFee);

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(tenantsProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
            children: [
              _header(),
              const SizedBox(height: 8),
              _gestureHint(),
              const SizedBox(height: 10),
              if (!_masked) ...[
                _kpiBar(rows, totalFee),
                const SizedBox(height: 12),
              ],
              ...rows.map(_storeCard),
            ],
          ),
        );
      },
    );
  }

  // ── 제스처 안내 (스와이프/더블탭) ──
  Widget _gestureHint() {
    return Row(children: const [
      Icon(Icons.swipe_left, size: 13, color: AppColors.dim),
      SizedBox(width: 5),
      Text('Desliza ← mensaje', style: TextStyle(color: AppColors.dim, fontSize: 10.5)),
      SizedBox(width: 12),
      Icon(Icons.touch_app, size: 13, color: AppColors.dim),
      SizedBox(width: 5),
      Text('doble-tap detalle', style: TextStyle(color: AppColors.dim, fontSize: 10.5)),
    ]);
  }

  // ── 헤더: 제목 + Hoy/Este mes 토글 + 눈 아이콘 ──
  Widget _header() {
    Widget segBtn(String label, bool mesVal) {
      final on = _mes == mesVal;
      return GestureDetector(
        onTap: () => setState(() => _mes = mesVal),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: on ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? AppColors.navy : AppColors.dim, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      );
    }

    return Row(
      children: [
        const Text('Clientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.panel,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [segBtn('Hoy', false), segBtn('Este mes', true)]),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => setState(() => _masked = !_masked),
          child: Container(
            width: 36,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_masked ? Icons.visibility_off : Icons.visibility,
                size: 19, color: AppColors.dim),
          ),
        ),
        const SizedBox(width: 8),
        // Borrados(삭제된 매장) 화면 진입
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BorradosScreen()),
          ),
          child: Container(
            width: 36,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.delete_sweep_outlined, size: 19, color: AppColors.dim),
          ),
        ),
      ],
    );
  }

  // ── KPI 3칸 (가림 시 숨김) ──
  Widget _kpiBar(List<Tenant> rows, num totalFee) {
    Widget k(String label, String val, String note, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(label, style: const TextStyle(color: AppColors.dim, fontSize: 9.5)),
              const SizedBox(height: 3),
              Text(val, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 1),
              Text(note, style: const TextStyle(color: AppColors.dim, fontSize: 9)),
            ]),
          ),
        );
    // Phase A: 수납 원장 미배포 → Cobrado 0, Por cobrar 전액.
    return Row(children: [
      k('A cobrar (mes)', _fee(totalFee), '${rows.length} tiendas', AppColors.gold),
      k('Cobrado', _fee(0), '0 pagadas', AppColors.green),
      k('Por cobrar', _fee(totalFee), '${rows.length} pendientes', AppColors.amber),
    ]);
  }

  // ── 매장 카드 (스와이프←=메시지, 더블탭=상세) ──
  Widget _storeCard(Tenant t) {
    final st = _statusOf(t);
    final card = Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더 줄
        Row(children: [
          Container(width: 11, height: 11, margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(color: st.$2, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.storeName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('última · ${_ago(t.lastActivityAt)}',
                  style: TextStyle(color: st.$2, fontSize: 11)),
            ]),
          ),
          if (_mes)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              RichText(
                  text: TextSpan(children: [
                TextSpan(text: '${t.activeDaysMonth}',
                    style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800, fontSize: 20)),
                TextSpan(text: ' /${DateTime.now().day} días',
                    style: const TextStyle(color: AppColors.dim, fontSize: 11)),
              ])),
              Text('usó el sistema', style: TextStyle(color: st.$2, fontSize: 10, fontWeight: FontWeight.w700)),
            ])
          else
            Text(st.$1, style: TextStyle(color: st.$2, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
        // Mes: 히트맵
        if (_mes) ...[
          const SizedBox(height: 11),
          _heatmap(t),
          const SizedBox(height: 2),
          const Text('días del mes · verde = usó ese día', style: TextStyle(color: AppColors.dim, fontSize: 9.5)),
        ],
        // 사용량 칩
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: _chips(t)),
        // 모듈 + 요금
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.only(top: 9),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(children: [
            Expanded(child: Wrap(spacing: 5, runSpacing: 5, children: _mods(t))),
            const SizedBox(width: 8),
            Text(_fee(t.expectedFee),
                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: GestureDetector(
        onDoubleTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StoreDetailScreen(tenant: t)),
        ),
        child: Slidable(
          key: ValueKey(t.storeId),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.26,
            children: [
              CustomSlidableAction(
                onPressed: (_) => showStoreMessageSheet(context, ref, t),
                backgroundColor: AppColors.cyan,
                foregroundColor: Colors.white,
                borderRadius: BorderRadius.circular(14),
                padding: EdgeInsets.zero,
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mail_outline, size: 22),
                  SizedBox(height: 5),
                  Text('Mensaje', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ),
          child: card,
        ),
      ),
    );
  }

  List<Widget> _chips(Tenant t) {
    final items = _mes
        ? [
            ('🧾', 'Ventas', t.salesMonth),
            ('👗', 'VTO', t.vtoMonth),
            ('💬', 'WhatsApp', t.whatsappMonth),
            ('📄', 'Fac.E', t.facturasMonth),
          ]
        : [
            ('🧾', 'Ventas', t.salesToday),
            ('👗', 'VTO', t.vtoToday),
            ('💬', 'WhatsApp', t.whatsappToday),
            ('📄', 'Fac.E', t.facturasToday),
            ('📱', 'Vend', t.vendedorDevices),
          ];
    return items.map((e) {
      final zero = e.$3 == 0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.navy2,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Opacity(
          opacity: zero ? 0.45 : 1,
          child: Text('${e.$1} ${e.$2} ${e.$3}',
              style: const TextStyle(color: AppColors.txt, fontSize: 10.5)),
        ),
      );
    }).toList();
  }

  List<Widget> _mods(Tenant t) {
    final mods = <(String, bool)>[
      ('Fac.E', t.modFacturaElectronica),
      ('WhatsApp', t.modWhatsapp),
      ('WP', t.modWoocommerce),
      ('TiendaNube', t.modTiendanube),
      ('VTO', t.modVto),
      ('Vendedor', t.modVendedor),
    ];
    return mods.map((m) {
      final up = m.$2;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: up ? AppColors.green.withOpacity(0.10) : AppColors.navy2,
          border: Border.all(color: up ? AppColors.green.withOpacity(0.5) : AppColors.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(m.$1,
            style: TextStyle(color: up ? AppColors.green : AppColors.dim, fontSize: 9.5)),
      );
    }).toList();
  }

  Widget _heatmap(Tenant t) {
    final elapsed = DateTime.now().day;
    final active = t.activeDayNums.toSet();
    return Wrap(spacing: 3, runSpacing: 3, children: [
      for (var d = 1; d <= elapsed; d++)
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: active.contains(d) ? AppColors.green : const Color(0xFF26324A),
            borderRadius: BorderRadius.circular(3),
            border: d == elapsed ? Border.all(color: AppColors.gold, width: 1.2) : null,
          ),
        ),
    ]);
  }

  // 활동 상태 (label, color, dotState)
  (String, Color, String) _statusOf(Tenant t) {
    final la = t.lastActivityAt;
    if (la == null) return ('Inactiva', AppColors.dim, 'off');
    final now = DateTime.now();
    final mins = now.difference(la).inMinutes;
    final sameDay = la.year == now.year && la.month == now.month && la.day == now.day;
    if (mins <= 5) return ('En línea', AppColors.green, 'on');
    if (sameDay) return ('Activa hoy', AppColors.green, 'on');
    if (now.difference(la).inDays <= 3) return ('Sin uso hoy', AppColors.amber, 'idle');
    return ('Inactiva', AppColors.dim, 'off');
  }

  String _ago(DateTime? la) {
    if (la == null) return 'sin datos';
    final d = DateTime.now().difference(la);
    if (d.inMinutes < 1) return 'recién';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }
}
