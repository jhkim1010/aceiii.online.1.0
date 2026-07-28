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
                    Text('${o.openCount} / ${o.boxes.length}',
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
        if (o.boxes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(
                child: Text('No hay cajas',
                    style: TextStyle(color: AppColors.dim))),
          ),
        for (final b in o.boxes) ...[
          _BoxCard(box: b),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}

// 카하(box) 1개 카드 — 터미널은 노출하지 않는다. 탭하면 열린 세션 상세로 이동.
class _BoxCard extends StatelessWidget {
  final CajaBoxStatus box;
  const _BoxCard({required this.box});

  void _open(BuildContext context) {
    final open = box.openSessions;
    if (open.length == 1) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CajaDetailScreen(session: open.first),
      ));

      return;
    }
    if (open.length > 1) {
      // 같은 카하에 열린 세션이 여러 개(비정상 잔재 포함) → 선택 시트
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.panel,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in open)
                ListTile(
                  leading: const Icon(Icons.point_of_sale,
                      color: AppColors.gold, size: 20),
                  title: Text(s.userName,
                      style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                      '${s.date}${s.startTime != null ? ' · ${_hm(s.startTime!)}' : ''}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.dim)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CajaDetailScreen(session: s),
                    ));
                  },
                ),
            ],
          ),
        ),
      );

      return;
    }

    // 닫힌 카하: 오늘 마감된 세션이 있으면 최근 것을 보여준다
    if (box.todaySessions.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CajaDetailScreen(session: box.todaySessions.last),
      ));

      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Esta caja no tuvo actividad hoy.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final open = box.isOpen;
    final firstOpen = open ? box.openSessions.first : null;

    return GestureDetector(
      onTap: () => _open(context),
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
                    child: Text(box.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),

                  // 유령 세션 경고: 삭제된 터미널 / 이전 날짜 미마감
                  if (box.hasDeletedTerminal) ...[
                    const SizedBox(width: 6),
                    const _WarnChip('Sesión huérfana'),
                  ] else if (box.hasStaleOpen) ...[
                    const SizedBox(width: 6),
                    const _WarnChip('Sin cerrar'),
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
                        Text(
                            open
                                ? box.openSessions
                                    .map((s) => s.userName)
                                    .toSet()
                                    .join(', ')
                                : 'Sin sesión abierta',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (box.branchName != null) box.branchName!,
                            if (firstOpen?.startTime != null)
                              'Apertura ${_hm(firstOpen!.startTime!)}',
                            if (!open && box.todaySessions.isNotEmpty)
                              'Cerrada hoy',
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.dim),
                        ),
                      ],
                    ),
                  ),
                  if (open)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(box.balance),
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
