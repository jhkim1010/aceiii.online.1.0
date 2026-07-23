import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import '../../shared/nav_state.dart';
import '../caja/caja_repository.dart';
import 'dashboard_repository.dart';

class PanelScreen extends ConsumerWidget {
  const PanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(salesSummaryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(salesSummaryProvider);
        ref.invalidate(cajaOverviewProvider);
        await ref.read(salesSummaryProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _ErrorBox(
              msg: 'No se pudo cargar el panel.',
              detail: '$e',
              onRetry: () => ref.invalidate(salesSummaryProvider),
            ),
            data: (s) => _summaryBody(context, s),
          ),
          const SizedBox(height: 12),
          _CajaLiveCard(),
        ],
      ),
    );
  }

  Widget _summaryBody(BuildContext context, SalesSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Kpi(
                label: 'Ventas hoy',
                value: money(s.ventasHoy),
                color: AppColors.gold,
                delta: s.ventasChange,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _Kpi(
                label: 'Ingreso',
                value: money(s.ingresoHoy),
                color: AppColors.green,
                delta: s.ingresoChange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: _Kpi(
                label: 'Gastos',
                value: money(s.gastosHoy),
                color: AppColors.red,
                delta: s.gastosChange,
                invertDelta: true,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _Kpi(
                label: 'Facturas pend.',
                value: '${s.facturasPendientes}',
                color: AppColors.cyan,
                caption: 'por cobrar',
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: _Kpi(
                label: 'Descuentos',
                value: money(s.descuentosHoy),
                color: AppColors.txt,
                caption: 'aplicados hoy',
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: _Kpi(
                label: 'Clientes',
                value: '${s.totalClientes}',
                color: AppColors.txt,
                caption: 'registrados',
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        _WeekCard(data: s.ventasSemana),
      ],
    );
  }
}

// ── 위젯들 ──

class _Card extends StatelessWidget {
  final Widget child;
  final Color? border;
  const _Card({required this.child, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? AppColors.line),
      ),
      child: child,
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final num? delta;
  final bool invertDelta;
  final String? caption;
  const _Kpi({
    required this.label,
    required this.value,
    required this.color,
    this.delta,
    this.invertDelta = false,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    Widget? sub;
    if (delta != null) {
      final up = delta! >= 0;
      // 지출은 증가가 나쁨 → 색 반전
      final good = invertDelta ? !up : up;
      sub = Text(
        '${up ? '▲' : '▼'} ${pct(delta!.abs())} vs ayer',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: good ? AppColors.green : AppColors.red,
        ),
      );
    } else if (caption != null) {
      sub = Text(caption!,
          style: const TextStyle(fontSize: 10.5, color: AppColors.dim));
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dim)),
          const SizedBox(height: 5),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800, color: color)),
          if (sub != null) ...[const SizedBox(height: 4), sub],
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final List<({String day, num total})> data;
  const _WeekCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxV =
        data.fold<num>(1, (a, b) => b.total > a ? b.total : a).toDouble();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VENTAS · ÚLTIMA SEMANA',
              style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dim)),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: data.isEmpty
                ? const Center(
                    child: Text('Sin datos',
                        style: TextStyle(color: AppColors.dim, fontSize: 12)))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in data)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Container(
                              height: (d.total / maxV * 44).clamp(3, 44),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.gold,
                                    Color(0x40F5A623),
                                  ],
                                ),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// Panel 하단 Caja 실시간 요약 카드 → 탭하면 Caja 탭으로 이동.
class _CajaLiveCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cajaOverviewProvider);

    return GestureDetector(
      onTap: () => ref.read(navIndexProvider.notifier).state = 1,
      child: _Card(
        border: AppColors.gold.withValues(alpha: 0.35),
        child: async.when(
          loading: () => const SizedBox(
            height: 54,
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (e, _) => const SizedBox(
            height: 40,
            child: Center(
                child: Text('Caja no disponible',
                    style: TextStyle(color: AppColors.dim, fontSize: 12))),
          ),
          data: (o) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('CAJA · EN VIVO',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold)),
                  const Spacer(),
                  _Pill(
                    text: '${o.openCount} abiertas',
                    color: AppColors.green,
                    dot: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(money(o.totalSaldo),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  const Text('saldo actual',
                      style: TextStyle(color: AppColors.dim, fontSize: 11)),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppColors.dim),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool dot;
  const _Pill({required this.text, required this.color, this.dot = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  final String detail;
  final VoidCallback onRetry;
  const _ErrorBox(
      {required this.msg, required this.detail, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(msg,
              style: const TextStyle(
                  color: AppColors.red, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.dim, fontSize: 11)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
