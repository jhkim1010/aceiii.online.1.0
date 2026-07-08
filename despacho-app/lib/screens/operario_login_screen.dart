import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/operario.dart';
import '../providers/app_providers.dart';

/// 작업자 로그인 — 이름 선택 그리드 → PIN 검증. 성공 시 operario 설정.
/// 기기(디바이스)는 이미 인증된 상태에서 "누가" 일하는지만 정한다.
class OperarioLoginScreen extends ConsumerStatefulWidget {
  const OperarioLoginScreen({super.key});

  @override
  ConsumerState<OperarioLoginScreen> createState() => _OperarioLoginScreenState();
}

class _OperarioLoginScreenState extends ConsumerState<OperarioLoginScreen> {
  Operario? _selected;
  final _pinCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final pin = _pinCtrl.text.trim();
    if (_selected == null) return;
    if (pin.isEmpty) {
      setState(() => _error = 'Ingresá tu PIN.');

      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('Dispositivo no autenticado');
      final op = await api.verifyOperario(_selected!.id, pin);
      await ref.read(operarioProvider.notifier).setOperario(op);
      // 성공 → main 라우팅이 HomeShell 로 전환.
    } catch (e) {
      setState(() {
        _error = 'PIN incorrecto';
        _submitting = false;
        _pinCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('¿Quién sos?'),
        actions: [
          IconButton(
            tooltip: 'Cambiar dispositivo',
            icon: const Icon(Icons.settings),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: _selected == null ? _nameGrid() : _pinEntry(),
    );
  }

  Widget _nameGrid() {
    final operariosAsync = ref.watch(operariosProvider);

    return operariosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$e', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay operarios cargados.\nCargalos en Ventas Online > Operarios.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return GridView.count(
          padding: const EdgeInsets.all(20),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: list.map((op) {
            return ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
              ),
              onPressed: () => setState(() {
                _selected = op;
                _error = null;
                _pinCtrl.clear();
              }),
              child: Text(op.name, textAlign: TextAlign.center),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _pinEntry() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _selected!.name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('Ingresá tu PIN',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              TextField(
                controller: _pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(
                  counterText: '',
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFF5A623))),
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: const Color(0xFF0F0F1E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _submitting ? null : _verify,
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: _submitting ? null : () => setState(() => _selected = null),
                child: const Text('← Elegir otro', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
