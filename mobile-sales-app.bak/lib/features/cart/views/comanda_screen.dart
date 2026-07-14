// S4 Comanda/Carrito (/comanda) — 라인(변형 단위) + stepper + totbox + cliente(opcional)
// + 하단 CTA "🧾 Mandar a Caja"(gold, D-13 보류 생성). 결제수단/금전함 UI 없음.
// OFFLINE GUARD (criterion #11): 오프라인이면 CTA disabled + "Requiere conexión" 안내.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format/money.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../data/sale_repository.dart';
import '../providers/cart_provider.dart';
import '../../done/views/done_screen.dart';

class ComandaScreen extends ConsumerStatefulWidget {
  const ComandaScreen({super.key});

  @override
  ConsumerState<ComandaScreen> createState() => _ComandaScreenState();
}

class _ComandaScreenState extends ConsumerState<ComandaScreen> {
  final _clientController = TextEditingController();
  bool _sending = false;

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

  Future<void> _sendToCaja() async {
    if (_sending) {
      return;
    }
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    // 완료 화면 reserva 표시용 — 전송 전 스냅샷
    final reservas = cart.lines
        .map((l) => DoneReserva(
              label: '${l.colorName} · Talle ${l.sizeName}',
              qty: l.quantity,
              remaining: (l.ownAvailable - l.quantity).clamp(0, l.ownAvailable),
            ))
        .toList();
    try {
      final result = await ref.read(saleRepositoryProvider).sendToCaja(cart);
      ref.read(cartProvider.notifier).clear();
      if (!mounted) {
        return;
      }
      context.go('/done', extra: DoneArgs(suspendedSaleId: result.suspendedSaleId, reservas: reservas));
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.red,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final online = ref.watch(isOnlineProvider).value ?? true;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => context.pop(),
        ),
        title: const Text('Carrito', style: TextStyle(fontSize: 17)),
      ),
      body: cart.isEmpty
          ? const _EmptyCart()
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      for (final line in cart.lines) _CartLineTile(line: line),
                      const SizedBox(height: 8),
                      // cliente (opcional)
                      TextField(
                        controller: _clientController,
                        onChanged: (v) => ref.read(cartProvider.notifier).setClientName(v),
                        decoration: const InputDecoration(
                          labelText: 'Nombre del cliente (opcional)',
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                _TotBox(units: cart.totalUnits, total: cart.subtotal),
                _CtaBar(
                  online: online,
                  sending: _sending,
                  onSend: _sendToCaja,
                ),
              ],
            ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🛒', style: TextStyle(fontSize: 44)),
            SizedBox(height: 12),
            Text(
              'El carrito está vacío. Escaneá el QR o buscá un producto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  final CartLine line;

  const _CartLineTile({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.soft,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('🏷️', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${line.colorName} · Talle ${line.sizeName}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  formatMoney(line.subtotal),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),
          // stepper (−/N/+) — + 는 자지점 available 한도(UI-D2)
          _StepButton(
            icon: Icons.remove,
            onTap: () => notifier.decrement(line.variantKey),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${line.quantity}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: kTabularFigures,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onTap: () {
              final ok = notifier.increment(line.variantKey);
              if (!ok) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Sin disponible')));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.ink),
      ),
    );
  }
}

class _TotBox extends StatelessWidget {
  final int units;
  final double total;

  const _TotBox({required this.units, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _row('Artículos', '$units u'),
          const SizedBox(height: 4),
          _row('Descuento', formatMoney(0)),
          const Divider(height: 16),
          _row('Total', formatMoney(total), bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold ? AppColors.ink : AppColors.muted,
            )),
        Text(value,
            style: TextStyle(
              fontSize: bold ? 17 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.ink,
              fontFeatures: kTabularFigures,
            )),
      ],
    );
  }
}

// 하단 CTA — 오프라인이면 disabled + 안내 (criterion #11)
class _CtaBar extends StatelessWidget {
  final bool online;
  final bool sending;
  final VoidCallback onSend;

  const _CtaBar({required this.online, required this.sending, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!online)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.amberSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '📴 Requiere conexión para mandar a caja',
                  style: TextStyle(color: AppColors.goldDark, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ElevatedButton(
              style: AppTheme.goldCtaStyle,
              onPressed: (online && !sending) ? onSend : null,
              child: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy2),
                    )
                  : const Text('🧾 Mandar a Caja'),
            ),
          ],
        ),
      ),
    );
  }
}
