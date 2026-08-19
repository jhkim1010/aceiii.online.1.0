import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'cobranzas_repository.dart';

// 관리비 수납 — 검토 대기 comprobante 와 월별 현황.
//
// ★ 버튼 문구가 **"Confirmar acreditación"**(입금 확인)이지 "영수증 발급" 이 아니다.
//   서류를 승인하는 것과 돈이 들어온 걸 승인하는 것을 같은 말로 부르면,
//   서류만 보고 누르게 된다.
//
// ★ 금액 비교와 중복 참조 경고는 **서버가 이미 판정해서** 온다. 앱이 다시 계산하면
//   웹과 다른 답을 갖게 되고, 그러면 어느 쪽이 맞는지 아무도 모른다.
//
// ★ 폰에서도 원본을 크게 볼 수 있어야 한다 — 이체 캡처의 금액·참조번호를 못 읽으면
//   확인이 아니라 추측이 된다. 탭하면 전체 화면으로 확대된다(신분증 확인과 같은 방식).
class CobranzasScreen extends ConsumerStatefulWidget {
  const CobranzasScreen({super.key});

  @override
  ConsumerState<CobranzasScreen> createState() => _CobranzasScreenState();
}

class _CobranzasScreenState extends ConsumerState<CobranzasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = ref.watch(cobranzasPendientesProvider);
    final cuantos = pendientes.asData?.value.length ?? 0;

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.dim,
          indicatorColor: AppColors.gold,
          tabs: [
            Tab(text: cuantos > 0 ? 'Por revisar · $cuantos' : 'Por revisar'),
            const Tab(text: 'Estado mensual'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_PendientesTab(), _ResumenTab()],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PendientesTab extends ConsumerWidget {
  const _PendientesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(cobranzasPendientesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(cobranzasPendientesProvider),
      child: pendientes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Error al cargar: $e',
                style: const TextStyle(color: AppColors.red)),
          ],
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 80),
                Icon(Icons.inbox_outlined, size: 48, color: AppColors.dim),
                SizedBox(height: 12),
                Center(
                  child: Text('No hay comprobantes esperando revisión',
                      style: TextStyle(color: AppColors.dim)),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _PendienteCard(row: rows[i]),
          );
        },
      ),
    );
  }
}

class _PendienteCard extends ConsumerStatefulWidget {
  final CobranzaPendiente row;
  const _PendienteCard({required this.row});

  @override
  ConsumerState<_PendienteCard> createState() => _PendienteCardState();
}

class _PendienteCardState extends ConsumerState<_PendienteCard> {
  static final _money =
      NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);

  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: r.coincide ? AppColors.green : AppColors.red,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.storeName} · ${_periodo(r.billingPeriod)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    if (r.payerName != null && r.payerName!.isNotEmpty)
                      Text('Transfirió ${r.payerName}',
                          style: const TextStyle(
                              color: AppColors.dim, fontSize: 12)),
                  ],
                ),
              ),
              _chip(
                r.coincide ? 'Coincide' : 'No coincide',
                r.coincide ? AppColors.green : AppColors.red,
              ),
            ]),

            const SizedBox(height: 10),

            // 서버가 판정한 금액 비교 — 사람이 암산하면 부분납이 완납이 된다.
            Wrap(spacing: 18, runSpacing: 8, children: [
              _dato('Facturado', _money.format(r.facturado)),
              _dato('Saldo antes', _money.format(r.saldoAntes)),
              _dato('Declarado', _money.format(r.declarado),
                  color: r.coincide ? AppColors.green : AppColors.red),
              _dato('Depósito', r.depositDate),
              _dato('Medio', r.method),
              _dato('Ref.', r.reference ?? '—'),
            ]),

            if (!r.coincide) ...[
              const SizedBox(height: 10),
              _aviso(
                r.diferencia < 0
                    ? 'Faltan ${_money.format(r.diferencia.abs())}. Si confirmás, queda como pago parcial y el saldo sigue abierto.'
                    : 'Declara ${_money.format(r.diferencia)} de más respecto del saldo.',
                AppColors.red,
              ),
            ],

            // ★ 같은 참조번호 재사용 — 가장 흔한 조용한 사고다.
            if (r.referenciaRepetida) ...[
              const SizedBox(height: 8),
              _aviso(
                'Ese nº de referencia ya aparece en otro comprobante. Verificá que no sea el mismo depósito.',
                AppColors.amber,
              ),
            ],

            if (r.fileKey != null) ...[
              const SizedBox(height: 12),
              _Archivo(submissionId: r.submissionId),
            ],

            const Divider(height: 24, color: AppColors.line),

            const Text('Verificá la acreditación en el banco antes de confirmar.',
                style: TextStyle(color: AppColors.dim, fontSize: 12)),
            const SizedBox(height: 8),

            Row(children: [
              TextButton(
                onPressed: _busy ? null : _rechazar,
                child: const Text('Rechazar',
                    style: TextStyle(color: AppColors.dim)),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _confirmar,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Confirmar acreditación'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.black),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _periodo(String raw) =>
      raw.length >= 7 ? raw.substring(0, 7) : raw;

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _dato(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.dim, fontSize: 11)),
          Text(value,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
        ],
      );

  Widget _aviso(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.30)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
      );

  Future<void> _confirmar() async {
    final r = widget.row;

    // ★ 금액이 안 맞으면 한 번 더 묻는다 — 부분납으로 남는다는 걸 알고 눌러야 한다.
    if (!r.coincide) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('El importe no coincide'),
          content: Text(
            'Se va a registrar ${_money.format(r.declarado)} sobre un saldo de '
            '${_money.format(r.saldoAntes)}. El resto queda pendiente.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar igual')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(cobranzasRepositoryProvider)
          .confirmarAcreditacion(r.submissionId, amount: r.declarado);
      ref.invalidate(cobranzasPendientesProvider);
      ref.invalidate(facturasMesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acreditación confirmada')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al confirmar: $e')));
    }
  }

  Future<void> _rechazar() async {
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar comprobante'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Motivo — el cliente lo va a ver',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (motivo == null || motivo.length < 5) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(cobranzasRepositoryProvider)
          .rechazar(widget.row.submissionId, motivo);
      ref.invalidate(cobranzasPendientesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comprobante rechazado')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al rechazar: $e')));
    }
  }
}

/// comprobante 원본. 탭하면 전체 화면으로 확대된다 — 금액·참조번호를 못 읽으면
/// 확인이 아니라 추측이 된다.
class _Archivo extends ConsumerWidget {
  final int submissionId;
  const _Archivo({required this.submissionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Uint8List>(
      future: ref.read(cobranzasRepositoryProvider).getArchivo(submissionId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return const SizedBox(
            height: 60,
            child: Center(
              child: Text('No se pudo abrir el comprobante',
                  style: TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          );
        }

        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(8),
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.memory(snap.data!),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              snap.data!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,

              // PDF 등 이미지가 아닌 첨부는 미리보기가 안 된다 — 조용히 깨지는 대신
              // 그렇다고 말한다.
              errorBuilder: (_, _, _) => Container(
                height: 60,
                alignment: Alignment.center,
                child: const Text('Adjunto no visualizable (¿PDF?)',
                    style: TextStyle(color: AppColors.dim, fontSize: 12)),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ResumenTab extends ConsumerStatefulWidget {
  const _ResumenTab();

  @override
  ConsumerState<_ResumenTab> createState() => _ResumenTabState();
}

class _ResumenTabState extends ConsumerState<_ResumenTab> {
  static final _money =
      NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);

  bool _generando = false;

  @override
  Widget build(BuildContext context) {
    final facturas = ref.watch(facturasMesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(facturasMesProvider),
      child: facturas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Error al cargar: $e',
                style: const TextStyle(color: AppColors.red)),
          ],
        ),
        data: (rows) {
          final total = rows.fold<num>(0, (a, f) => a + f.grandTotal);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: Text(_money.format(total),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                OutlinedButton.icon(
                  onPressed: _generando ? null : _generar,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_generando ? 'Generando…' : 'Generar borradores'),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Los borradores no facturan nada — se emiten después de revisar los importes.',
                style: TextStyle(color: AppColors.dim, fontSize: 12),
              ),
              const SizedBox(height: 14),

              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('Todavía no hay facturas para este período',
                        style: TextStyle(color: AppColors.dim)),
                  ),
                ),

              ...rows.map((f) => Card(
                    child: ListTile(
                      title: Text(f.receiverName ?? '#${f.storeId}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${_estadoEs(f.status)}'
                        '${f.fiscalVoucherNumber != null ? ' · ${f.fiscalVoucherNumber}' : ''}',
                        style: const TextStyle(
                            color: AppColors.dim, fontSize: 12.5),
                      ),
                      trailing: Text(_money.format(f.grandTotal),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  String _estadoEs(String s) => switch (s) {
        'draft' => 'Borrador',
        'issued' => 'Emitida — sin pagar',
        'partially_paid' => 'Pago parcial',
        'paid' => 'Pagada',
        'void' => 'Anulada',
        _ => s,
      };

  Future<void> _generar() async {
    setState(() => _generando = true);
    try {
      final r =
          await ref.read(cobranzasRepositoryProvider).generarBorradores();
      ref.invalidate(facturasMesProvider);
      if (!mounted) return;
      setState(() => _generando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Borradores: ${r['creados'] ?? 0} nuevos, ${r['actualizados'] ?? 0} actualizados'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _generando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
