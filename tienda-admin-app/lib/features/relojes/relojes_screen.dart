import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'relojes_repository.dart';

// 목록은 claim/revoke 후 ref.invalidate 로 재조회한다.
final relojesDevicesProvider =
    FutureProvider.autoDispose<List<WatchDevice>>((ref) {
  return ref.read(relojesRepositoryProvider).listDevices();
});

// 코드 입력 · 연결된 워치 목록 · 회수. D-06(페어링은 휴대폰에서만 입력) 진입점.
class RelojesScreen extends ConsumerStatefulWidget {
  const RelojesScreen({super.key});

  @override
  ConsumerState<RelojesScreen> createState() => _RelojesScreenState();
}

class _RelojesScreenState extends ConsumerState<RelojesScreen> {
  final _controller = TextEditingController();
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    // 입력 길이에 따라 버튼 활성/비활성을 즉시 반영.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 공백·하이픈 제거 + 대문자 — repository.claimCode 와 같은 정규화(화면에서는 길이 판정용).
  String get _normalized =>
      _controller.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _submit({required bool disabled}) async {
    if (disabled || _claiming || _normalized.length != 8) return;
    setState(() => _claiming = true);
    try {
      await ref.read(relojesRepositoryProvider).claimCode(_controller.text);
      if (!mounted) return;
      _controller.clear();
      _showSnack(
        'Reloj vinculado. En unos segundos muestra las ventas.',
        error: false,
      );
      ref.invalidate(relojesDevicesProvider);
    } on RelojesException catch (e) {
      if (!mounted) return;
      _showSnack(_claimMessage(e.error), error: true);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  void _showSnack(String text, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.red : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _claimMessage(ClaimError e) => switch (e) {
        ClaimError.invalid => 'Código inválido o vencido',
        ClaimError.notAdmin =>
          'Sólo el administrador de la tienda puede vincular relojes',
        ClaimError.tooMany => 'Demasiados intentos. Esperá un minuto.',
        ClaimError.network => 'Sin conexión',
      };

  Future<void> _confirmRevoke(WatchDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Quitar reloj'),
        content:
            Text('¿Quitar "${d.displayName}"? Dejará de ver las ventas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(relojesRepositoryProvider).revoke(d.id);
    ref.invalidate(relojesDevicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(relojesDevicesProvider);
    final notAdmin = async.hasError &&
        async.error is RelojesException &&
        (async.error! as RelojesException).error == ClaimError.notAdmin;

    return Scaffold(
      appBar: AppBar(title: const Text('Relojes vinculados')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(relojesDevicesProvider);
          try {
            await ref.read(relojesDevicesProvider.future);
          } catch (_) {
            // 에러는 아래 async.when 의 error 분기가 보여준다.
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            _inputCard(disabled: notAdmin),
            const SizedBox(height: 14),
            if (notAdmin)
              _notice(
                'Sólo el administrador de la tienda puede vincular relojes',
              )
            else
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _notice('No se pudo cargar la lista.'),
                data: (devices) => devices.isEmpty
                    ? _notice(
                        'Todavía no hay relojes vinculados. Abrí Ventago '
                        'Admin en el reloj para ver el código.',
                      )
                    : Column(
                        children: [for (final d in devices) _deviceRow(d)],
                      ),
              ),
            const SizedBox(height: 14),
            _tipCard(),
          ],
        ),
      ),
    );
  }

  Widget _inputCard({required bool disabled}) {
    final canSubmit = !disabled && !_claiming && _normalized.length == 8;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ingresá el código que muestra el reloj',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            enabled: !disabled,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            decoration: const InputDecoration(
              hintText: 'K7Q4-29XM',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSubmit ? () => _submit(disabled: disabled) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.navy,
              ),
              child: _claiming
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.navy,
                      ),
                    )
                  : const Text('Vincular reloj'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceRow(WatchDevice d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.watch_outlined, color: AppColors.gold, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastSeenLabel(d.lastSeenAt),
                    style: const TextStyle(
                      color: AppColors.dim,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _confirmRevoke(d),
              child:
                  const Text('Quitar', style: TextStyle(color: AppColors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.dim),
        ),
      ),
    );
  }

  // 위 버튼 설정 안내 1줄(D-10) — 목록이 비어도 항상 보인다.
  Widget _tipCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: const Text(
        '💡 En el reloj: Ajustes › Funciones avanzadas › Personalizar '
        'botones › Doble pulsación → Ventago Admin',
        style: TextStyle(fontSize: 11.5, color: AppColors.gold),
      ),
    );
  }
}

// 'sin uso todavía' / 'hace N min|h|días' — 이 화면 전용(단일 사용) 변환.
String _lastSeenLabel(String? lastSeenAt) {
  if (lastSeenAt == null || lastSeenAt.isEmpty) return 'sin uso todavía';
  final dt = DateTime.tryParse(lastSeenAt);
  if (dt == null) return 'sin uso todavía';
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} días';
}
