// RecepcionDialog — 수령 확인 바텀 시트 (D-08)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../envios/data/envio_dto.dart';
import '../providers/recepcion_provider.dart';

// 수령 확인 다이얼로그 — showModalBottomSheet로 표시
class RecepcionDialog extends ConsumerStatefulWidget {
  final EnvioDto envio;
  final VoidCallback? onSuccess;

  const RecepcionDialog({
    super.key,
    required this.envio,
    this.onSuccess,
  });

  @override
  ConsumerState<RecepcionDialog> createState() => _RecepcionDialogState();
}

class _RecepcionDialogState extends ConsumerState<RecepcionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _receivedController = TextEditingController();
  final _rejectedController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _receivedController.dispose();
    _rejectedController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(createRecepcionProvider).isLoading;

    // 수령 완료 후 성공 SnackBar + 다이얼로그 닫기
    ref.listen(createRecepcionProvider, (_, next) {
      if (next.hasValue && !next.isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recepción registrada'),
            backgroundColor: Colors.green,
          ),
        );

        // 성공 콜백 실행 후 바텀 시트 닫기
        widget.onSuccess?.call();
        Navigator.of(context).pop();
      } else if (next.hasError) {
        // 에러 발생 시 SnackBar로 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return Padding(
      // 키보드 올라올 때 바텀 시트도 함께 올라오도록
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Confirmar recepción',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // 발송 정보 요약
                Text(
                  'Lote: ${widget.envio.loteName ?? '#${widget.envio.loteId}'}  —  Pendiente: ${widget.envio.pendingQuantity}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const Divider(height: 24),

                // 수령 수량 입력
                TextFormField(
                  controller: _receivedController,
                  enabled: !isLoading,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Cantidad recibida *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa la cantidad recibida';
                    }

                    final received = int.tryParse(value) ?? 0;
                    final rejected = int.tryParse(_rejectedController.text) ?? 0;

                    if (received <= 0) {
                      return 'La cantidad debe ser mayor a 0';
                    }

                    // T-17-11: 수령량 + 불량량 <= 대기 수량 검증
                    if (received + rejected > widget.envio.pendingQuantity) {
                      return 'Total (${received + rejected}) supera el pendiente (${widget.envio.pendingQuantity})';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 불량 수량 입력
                TextFormField(
                  controller: _rejectedController,
                  enabled: !isLoading,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Cantidad rechazada',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cancel_outlined),
                  ),
                  validator: (value) {
                    final received = int.tryParse(_receivedController.text) ?? 0;
                    final rejected = int.tryParse(value ?? '0') ?? 0;

                    // T-17-11: 합계 검증
                    if (received + rejected > widget.envio.pendingQuantity) {
                      return 'Total supera el pendiente (${widget.envio.pendingQuantity})';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 메모 입력 (선택)
                TextFormField(
                  controller: _notesController,
                  enabled: !isLoading,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),

                // 확인 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 폼 검증 후 수령 확인 요청 실행
  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final received = int.parse(_receivedController.text);
    final rejected = int.tryParse(_rejectedController.text) ?? 0;
    final notes = _notesController.text.trim();

    ref.read(createRecepcionProvider.notifier).create((
      envioId: widget.envio.id,
      receivedQuantity: received,
      rejectedQuantity: rejected,
      notes: notes.isNotEmpty ? notes : null,
    ));
  }
}
