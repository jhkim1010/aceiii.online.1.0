// 로그인 화면 — 전화번호 + 4자리 PIN 입력 UI
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

// 폼 유효성 검증이 필요하므로 ConsumerStatefulWidget 사용
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // 로그인 버튼 처리
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await ref.read(authNotifierProvider.notifier).login(
          _phoneController.text.trim(),
          _pinController.text.trim(),
        );

    // 에러가 있으면 SnackBar로 표시
    final authState = ref.read(authNotifierProvider);
    if (authState.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.error.toString().replaceFirst('ApiException', 'Error')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 앱 아이콘
                  Icon(
                    Icons.handshake_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),

                  // 앱 이름
                  Text(
                    'Portal de Talleres',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),

                  // 부제목
                  Text(
                    'Ingrese sus credenciales para acceder',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 48),

                  // 전화번호 입력 필드
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !isLoading,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      hintText: 'Ingrese su número de teléfono',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El teléfono es requerido';
                      }
                      if (value.trim().length < 7) {
                        return 'Ingrese un número de teléfono válido';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // 4자리 PIN 입력 필드
                  TextFormField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !isLoading,
                    decoration: const InputDecoration(
                      labelText: 'PIN (4 dígitos)',
                      hintText: '••••',
                      prefixIcon: Icon(Icons.lock_outlined),
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El PIN es requerido';
                      }
                      if (value.trim().length != 4) {
                        return 'El PIN debe tener exactamente 4 dígitos';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // 로그인 버튼 또는 로딩 인디케이터
                  SizedBox(
                    height: 52,
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Iniciar sesión',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
