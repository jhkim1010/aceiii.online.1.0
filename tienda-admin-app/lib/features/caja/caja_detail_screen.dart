import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import '../auth/auth_controller.dart';
import 'caja_repository.dart';
import 'caja_screen.dart' show CCard, StatusPill;

class CajaDetailScreen extends ConsumerStatefulWidget {
  final CajaSession session;
  const CajaDetailScreen({super.key, required this.session});

  @override
  ConsumerState<CajaDetailScreen> createState() => _CajaDetailScreenState();
}

class _CajaDetailScreenState extends ConsumerState<CajaDetailScreen> {
  bool _closing = false;

  CajaSession get session => widget.session;

  Future<void> _confirmClose() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Cerrar caja'),
        content: Text(
            '¿Cerrar la caja de ${session.terminalName} (${session.userName})? '
            'Esta acción transfiere el saldo a la caja fuerte.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar caja',
                  style: TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _closing = true);
    try {
      await ref.read(cajaRepositoryProvider).closeCaja(session.id);
      if (!mounted) return;
      ref.invalidate(cajaOverviewProvider);
      ref.invalidate(cajaResumeProvider(session.id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Caja cerrada.'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo cerrar la caja: $e'),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // 수동 이동 등록 (Ingreso / Retiro / Gasto) — 열린 카하 전용
  Future<void> _addMovement(String type) async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final label = switch (type) {
      'ingreso' => 'Ingreso',
      'retiro' => 'Retiro',
      _ => 'Gasto',
    };
    final color = switch (type) {
      'ingreso' => AppColors.cyan,
      'retiro' => AppColors.gold,
      _ => AppColors.red,
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        var saving = false;
        String? err;

        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> submit() async {
            final amount =
                num.tryParse(amountCtrl.text.replaceAll(',', '.'));
            if (amount == null || amount <= 0) {
              setSheet(() => err = 'Ingresá un monto válido.');

              return;
            }
            setSheet(() {
              saving = true;
              err = null;
            });
            try {
              await ref.read(cajaRepositoryProvider).addManualOperation(
                    cashRegisterId: session.id,
                    terminalId: session.terminalId,
                    type: type,
                    amount: amount,
                    description: descCtrl.text.trim(),
                    userId: ref.read(authControllerProvider).user?.id,
                  );
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              setSheet(() {
                saving = false;
                err = 'No se pudo registrar: $e';
              });
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Registrar $label',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Monto', prefixText: r'$ ', isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)', isDense: true),
                ),
                if (err != null) ...[
                  const SizedBox(height: 10),
                  Text(err!,
                      style:
                          const TextStyle(color: AppColors.red, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: saving ? null : submit,
                    child: Text(saving ? 'Guardando…' : 'Registrar $label',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );

    amountCtrl.dispose();
    descCtrl.dispose();
    if (saved == true && mounted) {
      // 잔액·이동 목록·목록 화면 요약 즉시 갱신
      ref.invalidate(cajaResumeProvider(session.id));
      ref.invalidate(cajaMovementsProvider(session.id));
      ref.invalidate(cajaOverviewProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$label registrado.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
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
      bottomNavigationBar: open
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: _closing ? null : _confirmClose,
                    icon: _closing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.lock_outline, size: 18),
                    label: Text(_closing ? 'Cerrando…' : 'Cerrar caja',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            )
          : null,
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
            if (open) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MovButton(
                      label: 'Ingreso',
                      icon: Icons.arrow_downward_rounded,
                      color: AppColors.cyan,
                      onTap: () => _addMovement('ingreso'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _MovButton(
                      label: 'Retiro',
                      icon: Icons.arrow_upward_rounded,
                      color: AppColors.gold,
                      onTap: () => _addMovement('retiro'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _MovButton(
                      label: 'Gasto',
                      icon: Icons.remove_circle_outline,
                      color: AppColors.red,
                      onTap: () => _addMovement('gasto'),
                    ),
                  ),
                ],
              ),
            ],
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

// 수동 이동 등록 버튼 (Ingreso / Retiro / Gasto)
class _MovButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MovButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  final BoxOp op;
  const _MoveRow({required this.op});

  @override
  Widget build(BuildContext context) {
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

  String _time(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final l = d.toLocal();

    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
