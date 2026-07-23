import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import 'caja_repository.dart';
import 'caja_screen.dart' show CCard, StatusPill;

class CajaDetailScreen extends ConsumerWidget {
  final CajaSession session;
  const CajaDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumeAsync = ref.watch(cajaResumeProvider(session.id));
    final movesAsync = ref.watch(cajaMovementsProvider(session.id));
    final open = session.isOpen;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(session.terminalName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text('${open ? 'Caja abierta' : 'Caja cerrada'} · ${session.userName}',
                style: const TextStyle(color: AppColors.dim, fontSize: 11.5)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cajaResumeProvider(session.id));
          ref.invalidate(cajaMovementsProvider(session.id));
          await ref.read(cajaResumeProvider(session.id).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            resumeAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => CCard(
                child: Text('No se pudo cargar el resumen.\n$e',
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
              data: (t) => _resume(t, open),
            ),
            const SizedBox(height: 16),
            const Text('MOVIMIENTOS',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dim)),
            const SizedBox(height: 9),
            movesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const Text('Movimientos no disponibles',
                  style: TextStyle(color: AppColors.dim, fontSize: 12)),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                          child: Text('Sin movimientos',
                              style: TextStyle(color: AppColors.dim))),
                    )
                  : CCard(
                      child: Column(
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0)
                              const Divider(height: 14, color: AppColors.line),
                            _MoveRow(op: list[i]),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resume(CajaTotals t, bool open) {
    return Column(
      children: [
        CCard(
          border: (open ? AppColors.green : AppColors.line)
              .withValues(alpha: open ? 0.35 : 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('SALDO FINAL ESTIMADO',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dim)),
                  const Spacer(),
                  StatusPill(open: open),
                ],
              ),
              const SizedBox(height: 6),
              Text(money(t.saldoFinal),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: open ? AppColors.green : AppColors.txt)),
            ],
          ),
        ),
        const SizedBox(height: 11),
        CCard(
          child: Column(
            children: [
              _amtRow('Monto inicial', t.initialAmount, AppColors.txt),
              const Divider(height: 16, color: AppColors.line),
              _amtRow('＋ Ventas', t.venta, AppColors.green),
              const Divider(height: 16, color: AppColors.line),
              _amtRow('＋ Ingresos', t.ingreso, AppColors.cyan),
              const Divider(height: 16, color: AppColors.line),
              _amtRow('－ Gastos', t.gasto, AppColors.red),
              const Divider(height: 16, color: AppColors.line),
              _amtRow('－ Retiros', t.retiro, AppColors.gold),
            ],
          ),
        ),
      ],
    );
  }

  Widget _amtRow(String label, num value, Color color) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(money(value),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

class _MoveRow extends StatelessWidget {
  final BoxOp op;
  const _MoveRow({required this.op});

  @override
  Widget build(BuildContext context) {
    // 부호/색: venta·ingreso = +초록/시안, gasto·retiro = -빨강/골드
    final isPlus = op.type == 'venta' || op.type == 'ingreso';
    final color = switch (op.type) {
      'venta' => AppColors.green,
      'ingreso' => AppColors.cyan,
      'gasto' => AppColors.red,
      'retiro' => AppColors.gold,
      _ => AppColors.txt,
    };
    final letter = op.type.isNotEmpty ? op.type[0].toUpperCase() : '?';

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.navy2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(letter,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(op.description.isEmpty ? op.type : op.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text(_time(op.createdAt) + (op.executionType == 'automatico' ? ' · auto' : ''),
                  style: const TextStyle(fontSize: 10.5, color: AppColors.dim)),
            ],
          ),
        ),
        Text('${isPlus ? '+' : '−'}${money(op.amount)}',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  // ISO createdAt → HH:mm
  String _time(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final l = d.toLocal();

    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
