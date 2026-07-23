import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

// 매장 카드 왼쪽 스와이프 → 이 시트로 개별 매장에 in-app 알림(store_notices) 발송.
// 기존 sendNotice(scope:'store', storeId) 재사용. 에러 핸들링 포함.
Future<void> showStoreMessageSheet(
  BuildContext context,
  WidgetRef ref,
  Tenant tenant,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.navy,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _StoreMessageSheet(tenant: tenant, parentRef: ref),
  );
}

class _StoreMessageSheet extends ConsumerStatefulWidget {
  final Tenant tenant;
  final WidgetRef parentRef;
  const _StoreMessageSheet({required this.tenant, required this.parentRef});

  @override
  ConsumerState<_StoreMessageSheet> createState() => _StoreMessageSheetState();
}

class _StoreMessageSheetState extends ConsumerState<_StoreMessageSheet> {
  String _level = 'info';
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  // 레벨별 색상 (info=cyan, warning=amber, dunning=red)
  Color _levelColor(String lv) => switch (lv) {
        'warning' => AppColors.amber,
        'dunning' => AppColors.red,
        _ => AppColors.cyan,
      };

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty || body.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final count = await ref.read(consoleRepositoryProvider).sendNotice(
            scope: 'store',
            level: _level,
            title: title,
            body: body,
            storeId: widget.tenant.storeId,
          );
      // 발송 이력 갱신 (mensajes 화면과 공유)
      widget.parentRef.invalidate(noticeHistoryProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.green,
          content: Text('Aviso enviado a ${widget.tenant.storeName} ($count).'),
        ),
      );
    } catch (e) {
      // 네트워크/서버 오류 — 시트 유지하고 메시지 표시
      if (mounted) setState(() => _error = 'No se pudo enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        _title.text.trim().isNotEmpty && _body.text.trim().isNotEmpty && !_sending;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    Widget levelChip(String value, String label) {
      final on = _level == value;
      final c = _levelColor(value);
      return GestureDetector(
        onTap: () => setState(() => _level = value),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.withOpacity(0.16) : AppColors.panel,
            border: Border.all(color: on ? c : AppColors.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? c : AppColors.dim,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5)),
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
                    color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              const Icon(Icons.mail_outline, color: AppColors.cyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Mensaje · ${widget.tenant.storeName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('Aviso in-app — llega solo a este local.',
                style: TextStyle(color: AppColors.dim, fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              levelChip('info', 'Info'),
              levelChip('warning', 'Aviso'),
              levelChip('dunning', 'Urgente'),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _body,
              maxLines: 4,
              maxLength: 5000,
              decoration: const InputDecoration(labelText: 'Mensaje para este local…'),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSend ? _send : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _levelColor(_level),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: Icon(_sending ? Icons.hourglass_top : Icons.send, size: 18),
                label: Text(_sending ? 'Enviando…' : 'Enviar aviso'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
