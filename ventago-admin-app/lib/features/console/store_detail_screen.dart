import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';
import 'store_message_sheet.dart';
import 'sessions_screen.dart';

// Clientes 카드 더블탭 → 매장 상세/setup 화면.
// 상태(오늘/이달)·예상 관리비·모듈 현황을 보여준다.
// 모듈 on/off 토글은 다음 단계(권한 계층)까지 읽기 전용(자물쇠).
class StoreDetailScreen extends ConsumerWidget {
  final Tenant tenant;
  const StoreDetailScreen({super.key, required this.tenant});

  static final _money =
      NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = _statusOf(tenant);

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('Detalle de cliente'),
        backgroundColor: AppColors.navy2,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
        children: [
          _headerCard(st),
          _cobroCard(context, ref),
          _actividadCard(),
          _modulosCard(),
          _dangerZone(context, ref),
        ],
      ),
      bottomSheet: _actionBar(context, ref),
    );
  }

  // ── 공통 카드 래퍼 ──
  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _lbl(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: AppColors.dim,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7)),
      );

  // ── 헤더 ──
  Widget _headerCard((String, Color, String) st) {
    final initial =
        tenant.storeName.trim().isEmpty ? '?' : tenant.storeName.trim()[0].toUpperCase();
    return _card(Row(children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(colors: [AppColors.gold, Color(0xFFFFCE6B)]),
        ),
        alignment: Alignment.center,
        child: Text(initial,
            style: const TextStyle(
                color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tenant.storeName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('store #${tenant.storeId}',
              style: const TextStyle(color: AppColors.dim, fontSize: 12)),
          const SizedBox(height: 7),
          Row(children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: st.$2, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(st.$1,
                style: TextStyle(color: st.$2, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('últ. ${_ago(tenant.lastActivityAt)}',
                  style: const TextStyle(color: AppColors.dim, fontSize: 11.5)),
            ),
            if (tenant.errors24h > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${tenant.errors24h} err 24h',
                    style: const TextStyle(
                        color: AppColors.red, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
          ]),
        ]),
      ),
    ]));
  }

  // ── 예상 관리비 (할인 반영) ──
  Widget _cobroCard(BuildContext context, WidgetRef ref) {
    final hasDiscount = tenant.recurringDiscount > 0 || tenant.oneTimeDiscount > 0;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('A cobrar · este mes'),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: _money.format(tenant.expectedFee),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            TextSpan(
                text: '  ${tenant.currency}',
                style: const TextStyle(color: AppColors.dim, fontSize: 14)),
          ])),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.amber.withOpacity(0.14),
            border: Border.all(color: AppColors.amber.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Pendiente',
              style: TextStyle(
                  color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
      // 할인 내역 (있을 때만)
      if (hasDiscount) ...[
        const SizedBox(height: 8),
        Text('Base ${_money.format(tenant.grossFee)}',
            style: const TextStyle(
                color: AppColors.dim,
                fontSize: 12,
                decoration: TextDecoration.lineThrough)),
        if (tenant.recurringDiscount > 0)
          Text('Desc. recurrente  −${_money.format(tenant.recurringDiscount)}',
              style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w700)),
        if (tenant.oneTimeDiscount > 0)
          Text('Desc. única vez (este mes)  −${_money.format(tenant.oneTimeDiscount)}',
              style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 11),
      Container(
        padding: const EdgeInsets.only(top: 10),
        decoration:
            const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(children: [
          Expanded(
            child: Text('${tenant.branches} sucursal(es) · ${tenant.terminals} terminal(es)',
                style: const TextStyle(color: AppColors.dim, fontSize: 12.5)),
          ),
          TextButton.icon(
            onPressed: () => _openDiscountSheet(context, ref),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
                padding: const EdgeInsets.symmetric(horizontal: 6)),
            icon: const Icon(Icons.sell_outlined, size: 16),
            label: const Text('Aplicar descuento',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ]),
      ),
    ]));
  }

  // 할인 입력 시트 열기 → 적용/제거 시 리스트로 복귀(순액 갱신)
  Future<void> _openDiscountSheet(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DiscountSheet(tenant: tenant, ref: ref),
    );
    if (applied == true) {
      ref.invalidate(tenantsProvider);
      if (context.mounted) Navigator.of(context).pop(); // 상세 닫기 → Clientes 리스트(순액 반영)
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.green,
        content: Text('Descuento actualizado en ${tenant.storeName}'),
      ));
    }
  }

  // ── 활동 (이달 días activos + 히트맵 + 오늘/이달 칩) ──
  Widget _actividadCard() {
    final elapsed = DateTime.now().day;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('Actividad'),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text.rich(TextSpan(children: [
          TextSpan(
              text: '${tenant.activeDaysMonth}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          TextSpan(
              text: ' / $elapsed días',
              style: const TextStyle(color: AppColors.dim, fontSize: 13)),
        ])),
        const Spacer(),
        Text(_mesEs(DateTime.now().month),
            style: const TextStyle(
                color: AppColors.dim, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      _heatmap(),
      const SizedBox(height: 4),
      const Text('verde = usó el sistema ese día',
          style: TextStyle(color: AppColors.dim, fontSize: 9.5)),
      const SizedBox(height: 13),
      const Text('Hoy',
          style: TextStyle(color: AppColors.dim, fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      Wrap(spacing: 7, runSpacing: 7, children: [
        _chip('🧾', 'ventas', tenant.salesToday),
        _chip('👗', 'VTO', tenant.vtoToday),
        _chip('💬', 'WhatsApp', tenant.whatsappToday),
        _chip('📄', 'Fac.E', tenant.facturasToday),
        _chip('📱', 'vend', tenant.vendedorDevices),
      ]),
      const SizedBox(height: 11),
      const Text('Este mes',
          style: TextStyle(color: AppColors.dim, fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      Wrap(spacing: 7, runSpacing: 7, children: [
        _chip('🧾', 'ventas', tenant.salesMonth),
        _chip('👗', 'VTO', tenant.vtoMonth),
        _chip('💬', 'WhatsApp', tenant.whatsappMonth),
        _chip('📄', 'Fac.E', tenant.facturasMonth),
      ]),
    ]));
  }

  Widget _chip(String emoji, String label, int n) {
    final zero = n == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.navy2,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Opacity(
        opacity: zero ? 0.45 : 1,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$emoji  '),
          TextSpan(
              text: '$n',
              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
          TextSpan(text: ' $label', style: const TextStyle(color: AppColors.dim, fontSize: 11)),
        ]), style: const TextStyle(color: AppColors.txt, fontSize: 12)),
      ),
    );
  }

  Widget _heatmap() {
    final elapsed = DateTime.now().day;
    final active = tenant.activeDayNums.toSet();
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (var d = 1; d <= elapsed; d++)
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: active.contains(d) ? AppColors.green : const Color(0xFF26324A),
            borderRadius: BorderRadius.circular(3.5),
            border: d == elapsed ? Border.all(color: AppColors.gold, width: 1.3) : null,
          ),
        ),
    ]);
  }

  // ── 모듈 (읽기 전용 자물쇠 스위치) ──
  Widget _modulosCard() {
    final mods = <(String, String, bool, String)>[
      ('📄', 'Factura electrónica', tenant.modFacturaElectronica, 'AFIP'),
      ('💬', 'WhatsApp', tenant.modWhatsapp, '${tenant.whatsappMonth} msg/mes'),
      ('🛒', 'WooCommerce', tenant.modWoocommerce, ''),
      ('🏬', 'TiendaNube', tenant.modTiendanube, ''),
      ('👗', 'Probador virtual (VTO)', tenant.modVto, '${tenant.vtoMonth} VTO/mes'),
      ('📱', 'App vendedor', tenant.modVendedor, '${tenant.vendedorDevices} disp.'),
    ];
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('Módulos & setup'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.amber.withOpacity(0.09),
          border: Border.all(color: AppColors.amber.withOpacity(0.22)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Row(children: [
          Icon(Icons.lock_outline, size: 14, color: AppColors.amber),
          SizedBox(width: 7),
          Expanded(
            child: Text('Ajuste de activación en la próxima fase — solo lectura',
                style: TextStyle(color: AppColors.amber, fontSize: 11)),
          ),
        ]),
      ),
      ...mods.map(_modRow),
    ]));
  }

  Widget _modRow((String, String, bool, String) m) {
    final on = m.$3;
    final sub = on ? (m.$4.isEmpty ? 'Activo' : 'Activo · ${m.$4}') : 'Inactivo';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1C2A48)))),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.navy2, borderRadius: BorderRadius.circular(10)),
          child: Text(m.$1, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.$2, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(
                    color: on ? AppColors.green : AppColors.dim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        // 읽기 전용 스위치 (자물쇠) — 다음 단계에서 활성화
        Opacity(
          opacity: 0.55,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44,
              height: 26,
              decoration: BoxDecoration(
                color: on ? const Color(0xFF2B6B52) : const Color(0xFF27364F),
                borderRadius: BorderRadius.circular(20),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: const BoxDecoration(
                      color: Color(0xFFDFE9FF), shape: BoxShape.circle),
                ),
              ),
            ),
            const Positioned(
              top: -7,
              right: -5,
              child: Icon(Icons.lock, size: 11, color: AppColors.dim),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── 하단 액션 바 ──
  Widget _actionBar(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: Row(children: [
        // 주 액션: 이 매장에 메시지
        Expanded(
          child: FilledButton.icon(
            onPressed: () => showStoreMessageSheet(context, ref, tenant),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.mail_outline, size: 19),
            label: const Text('Enviar mensaje',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
        const SizedBox(width: 10),
        // 보조 액션: 이 매장의 활성 세션 관제로 이동
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: AppColors.navy,
                appBar: AppBar(
                  backgroundColor: AppColors.navy2,
                  title: Text('Sesiones · ${tenant.storeName}'),
                ),
                body: SessionsScreen(initialStoreId: tenant.storeId),
              ),
            )),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cyan,
              side: const BorderSide(color: AppColors.line),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.devices_other, size: 18),
            label: const Text('Sesiones', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  // ── 위험 구역: 매장 soft-delete ──
  Widget _dangerZone(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: OutlinedButton.icon(
        onPressed: () => _confirmDelete(context, ref),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.red,
          side: BorderSide(color: AppColors.red.withOpacity(0.5)),
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.delete_outline, size: 19),
        label: const Text('Eliminar cliente', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Eliminar cliente'),
        content: Text(
            '¿Eliminar "${tenant.storeName}"?\n\n'
            'Se oculta de Clientes y su personal no podrá iniciar sesión. '
            'Podés restaurarlo desde Borrados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(consoleRepositoryProvider).softDeleteStore(tenant.storeId);
      ref.invalidate(tenantsProvider);
      ref.invalidate(deletedTenantsProvider);
      if (context.mounted) {
        Navigator.of(context).pop(); // 상세 닫기 → Clientes 로 복귀
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.red,
          content: Text('${tenant.storeName} eliminado. Restaurable en Borrados.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.red,
          content: Text('No se pudo eliminar: $e'),
        ));
      }
    }
  }

  // ── 상태/시간 헬퍼 (tenants_screen 과 동일 규칙) ──
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

  // 스페인어 월 이름 (intl 로케일 초기화 없이 안전하게)
  String _mesEs(int m) {
    const meses = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return (m >= 1 && m <= 12) ? meses[m - 1] : '';
  }
}

// 관리비 할인 입력 시트 — 금액 + 종류(recurrente/única vez) → 적용/제거.
class _DiscountSheet extends StatefulWidget {
  final Tenant tenant;
  final WidgetRef ref;
  const _DiscountSheet({required this.tenant, required this.ref});

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  final _monto = TextEditingController();
  String _kind = 'recurring';
  bool _sending = false;
  String? _error;

  final _fmt = NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    // 천단위 구분점(.) 제거 후 파싱
    final amount = num.tryParse(_monto.text.trim().replaceAll('.', '').replaceAll(',', '')) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Ingresá un monto válido');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.ref
          .read(consoleRepositoryProvider)
          .applyDiscount(widget.tenant.storeId, amount, _kind);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo aplicar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _remove(String kind) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.ref
          .read(consoleRepositoryProvider)
          .removeDiscount(widget.tenant.storeId, kind);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo quitar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tenant;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget kindChip(String value, String label, String sub) {
      final on = _kind == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _kind = value),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.gold.withOpacity(0.16) : AppColors.panel,
              border: Border.all(color: on ? AppColors.gold : AppColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(label,
                  style: TextStyle(
                      color: on ? AppColors.gold : AppColors.txt,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.dim, fontSize: 10)),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: AppColors.line, borderRadius: BorderRadius.circular(2))),
            ),
            Row(children: [
              const Icon(Icons.sell_outlined, color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Descuento · ${t.storeName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ]),
            // 현재 적용 중인 할인 (제거 가능)
            if (t.recurringDiscount > 0 || t.oneTimeDiscount > 0) ...[
              const SizedBox(height: 10),
              if (t.recurringDiscount > 0)
                _actualRow('Recurrente', _fmt.format(t.recurringDiscount), () => _remove('recurring')),
              if (t.oneTimeDiscount > 0)
                _actualRow('Única vez (este mes)', _fmt.format(t.oneTimeDiscount), () => _remove('one_time')),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: const InputDecoration(labelText: 'Monto del descuento', prefixText: r'$ '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(children: [
              kindChip('recurring', 'Recurrente', 'cada mes'),
              kindChip('one_time', 'Única vez', 'solo este mes'),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _apply,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.navy,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                icon: Icon(_sending ? Icons.hourglass_top : Icons.check, size: 18),
                label: Text(_sending ? 'Aplicando…' : 'Aplicar descuento',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actualRow(String label, String amount, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: Text('$label:  −$amount',
              style: const TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: _sending ? null : onRemove,
          style: TextButton.styleFrom(
              foregroundColor: AppColors.red,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: const Text('Quitar'),
        ),
      ]),
    );
  }
}
