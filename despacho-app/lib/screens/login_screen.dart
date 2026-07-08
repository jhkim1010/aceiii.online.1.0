import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../providers/app_providers.dart';

/// 로그인 화면.
/// Phase 1: baseUrl + 토큰(임시 JWT) 직접 입력 → 기존 엔드포인트로 조기 테스트.
/// Phase 2: 기기 apiKey 입력 → POST /despacho/auth 로 교체 예정.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _tokenCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El token de dispositivo es obligatorio')),
      );

      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(authProvider.notifier).signIn(token: token);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.local_shipping,
                      size: 64, color: Color(0xFFF5A623)),
                  const SizedBox(height: 12),
                  const Text(
                    'Ventago Despacho',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Preparación de pedidos',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),

                  // 서버 URL 은 코드 고정 — 입력창 제거(사용자 오입력 방지). 표시만.
                  Text(
                    AppConfig.defaultBaseUrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _tokenCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 2,
                    minLines: 1,
                    decoration: _dec('Token de dispositivo').copyWith(
                      // 붙여넣기 편의 — 클립보드 값 바로 채우기 버튼
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, color: Colors.white70),
                        tooltip: 'Pegar',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          final text = data?.text?.trim() ?? '';
                          if (text.isNotEmpty) {
                            setState(() => _tokenCtrl.text = text);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF5A623),
                      foregroundColor: const Color(0xFF0F0F1E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFF5A623)),
        ),
      );
}
