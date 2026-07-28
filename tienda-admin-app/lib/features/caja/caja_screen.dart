import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import 'caja_repository.dart';
import 'caja_detail_screen.dart';

class CajaScreen extends ConsumerWidget {
  const CajaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cajaOverviewProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(cajaOverviewProvider);
        await ref.read(cajaOverviewProvider.future);
      },
      child: async.when(
        loading: () => const _Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('No se pudo cargar la caja.',
                        style: TextStyle(
                            color: AppColors.red, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('$e',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: AppColors.dim, fontSize: 11)),
                    TextButton(
                        onPressed: () => ref.invalidate(cajaOverviewProvider),
                        child: const Text('Reintentar')),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (o) => _list(context, o),
      ),
    );
  }

  Widget _list(BuildContext context, CajaOverview o) {
    // 열린 것 먼저, 그 다음 닫힌 것
    final sessions = [...o.sessions]
      ..sort((a, b) => (a.isOpen == b.isOpen) ? 0 : (a.isOpen ? -1 : 1));

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: CCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Lbl('Saldo actual'),
                    const SizedBox(height: 5),
                    Text(money(o.totalSaldo),
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppColors.gold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: CCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Lbl('Cajas abiertas'),
                    const SizedBox(height: 5),
                    Text('${o.openCount} / ${o.sessions.length}',
                        style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(
                child: Text('No hay cajas hoy',
                    style: TextStyle(color: AppColors.dim))),
          ),
        for (final c in sessions) ...[
          _SessionCard(session: c),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final CajaSession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final open = session.isOpen;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CajaDetailScreen(session: session),
        ),
      ),
      child: Opacity(
        opacity: open ? 1 : 0.7,
        child: CCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: open ? AppColors.green : AppColors.red,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(session.boxName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),

                  // 유령 세션 경고: 삭제된 터미널 / 이전 날짜 미마감
                  if (session.terminalDeleted) ...[
                    const SizedBox(width: 6),
                    const _WarnChip('Terminal eliminada'),
                  ] else if (session.isStaleOpen) ...[
                    const SizedBox(width: 6),
                    _WarnChip('Sin cerrar ${_dm(session.date)}'),
                  ],
                  const Spacer(),
                  StatusPill(open: open),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.userName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (session.startTime != null)
                              'Apertura ${_hm(session.startTime!)}',
                            'inicial ${money(session.initialAmount)}',
                            if (session.branchName != null) session.branchName!,
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.dim),
                        ),
                      ],
                    ),
                  ),
                  if (open && session.saldo != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(session.saldo!),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.gold)),
                        const Text('saldo',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.dim)),
                      ],
                    )
                  else
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

// HH:mm:ss → HH:mm
String _hm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

// YYYY-MM-DD → DD/MM
String _dm(String d) {
  final p = d.split('-');

  return p.length == 3 ? '${p[2]}/${p[1]}' : d;
}

// 경고 칩 (유령 세션)
class _WarnChip extends StatelessWidget {
  final String text;
  const _WarnChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppColors.gold)),
    );
  }
}

// ── 공용 소형 위젯 (caja 화면 계열) ──

class CCard extends StatelessWidget {
  final Widget child;
  final Color? border;
  const CCard({super.key, required this.child, this.border});

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

class _Lbl extends StatelessWidget {
  final String text;
  const _Lbl(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: AppColors.dim));
  }
}

class StatusPill extends StatelessWidget {
  final bool open;
  const StatusPill({super.key, required this.open});

  @override
  Widget build(BuildContext context) {
    final color = open ? AppColors.green : AppColors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(open ? 'Abierta' : 'Cerrada',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _Center extends StatelessWidget {
  final Widget child;
  const _Center({required this.child});

  @override
  Widget build(BuildContext context) {
    // RefreshIndicator 아래에서도 당겨서 새로고침 가능하도록 스크롤 가능 레이아웃
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(child: child),
        ),
      ],
    );
  }
}
