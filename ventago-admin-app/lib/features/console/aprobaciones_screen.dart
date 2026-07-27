import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'onboarding_repository.dart';

// 신규 매장 가입 승인 화면.
// 승인해야 매장 + 오너 계정이 만들어진다 — 승인 전 신청자는 로그인할 수 없다.
class AprobacionesScreen extends ConsumerWidget {
  const AprobacionesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRegistrationsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pendingRegistrationsProvider),
      child: pending.when(
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
                Icon(Icons.verified_outlined,
                    size: 48, color: AppColors.dim),
                SizedBox(height: 12),
                Center(
                  child: Text('No hay solicitudes pendientes',
                      style: TextStyle(color: AppColors.dim)),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _card(context, ref, rows[i]),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, PendingRegistration r) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        title: Text(r.companyName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'CUIT ${r.companyCuit}\n${r.ownerName} · ${r.email}',
            style: const TextStyle(color: AppColors.dim, fontSize: 12),
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right, color: AppColors.dim),
        onTap: () => _openDetail(context, ref, r),
      ),
    );
  }

  void _openDetail(
      BuildContext context, WidgetRef ref, PendingRegistration r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DetailSheet(row: r),
    );
  }
}

class _DetailSheet extends ConsumerStatefulWidget {
  final PendingRegistration row;

  const _DetailSheet({required this.row});

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(r.companyName,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          if (r.aliasName != null && r.aliasName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('@${r.aliasName}',
                  style: const TextStyle(color: AppColors.gold)),
            ),
          const SizedBox(height: 16),
          _row('CUIT', r.companyCuit),
          _row('Dirección', r.companyAddress),
          _row('Titular', r.ownerName),
          _row('Usuario', r.username ?? '(se genera al aprobar)'),
          _row('Email', r.email, ok: r.emailVerified),
          _row('Teléfono', r.phone, ok: r.phoneVerified),
          _row('Solicitado', r.createdAt?.toLocal().toString().substring(0, 16) ?? '-'),
          const SizedBox(height: 18),
          const Text('DNI', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _dni(r.id, 'front', r.hasDniFront, 'Frente')),
              const SizedBox(width: 10),
              Expanded(child: _dni(r.id, 'back', r.hasDniBack, 'Dorso')),
            ],
          ),
          const SizedBox(height: 24),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reject,
                    icon: const Icon(Icons.close, color: AppColors.red),
                    label: const Text('Rechazar',
                        style: TextStyle(color: AppColors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _approve,
                    icon: const Icon(Icons.check),
                    label: const Text('Aprobar'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          const Text(
            'Al aprobar se crean la tienda y la cuenta del titular. '
            'Recién entonces podrá iniciar sesión.',
            style: TextStyle(color: AppColors.dim, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool? ok}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(color: AppColors.dim, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          if (ok != null)
            Icon(
              ok ? Icons.verified : Icons.error_outline,
              size: 16,
              color: ok ? AppColors.green : AppColors.amber,
            ),
        ],
      ),
    );
  }

  Widget _dni(int id, String side, bool exists, String label) {
    if (!exists) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$label\nno cargado',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.dim, fontSize: 12)),
      );
    }

    return FutureBuilder<Uint8List>(
      future: ref.read(onboardingRepositoryProvider).getDni(id, side),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Text('$label\nerror',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          );
        }

        return GestureDetector(
          // 탭 → 전체 화면 확대 (신분증 글씨 확인용)
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(8),
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(snap.data!),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(snap.data!,
                height: 120, width: double.infinity, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Aprobar la tienda?'),
        content: Text(
          'Se creará la tienda "${widget.row.companyName}" y la cuenta del titular. '
          'Esta acción no se puede deshacer desde la app.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprobar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final storeId =
          await ref.read(onboardingRepositoryProvider).approve(widget.row.id);
      ref.invalidate(pendingRegistrationsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Tienda aprobada${storeId > 0 ? ' (id $storeId)' : ''}. Ya puede iniciar sesión.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al aprobar: $e')));
    }
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Motivo (se guarda en el registro)',
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
    if (reason == null || reason.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(onboardingRepositoryProvider)
          .reject(widget.row.id, reason);
      ref.invalidate(pendingRegistrationsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Solicitud rechazada')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al rechazar: $e')));
    }
  }
}
