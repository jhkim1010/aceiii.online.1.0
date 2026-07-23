import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  // 비밀번호 표시/숨김 토글 (눈 아이콘)
  bool _obscure = true;
  // 지문 로그인 사용 가능(자격증명 저장됨 + 센서 존재)
  bool _canBio = false;

  @override
  void initState() {
    super.initState();
    // 화면 뜬 뒤 지문 가능하면 자동으로 프롬프트
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBiometric());
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _maybeBiometric() async {
    final ctrl = ref.read(authControllerProvider.notifier);
    final can = await ctrl.canUseBiometric();
    if (!mounted) return;
    setState(() => _canBio = can);
    if (can) {
      await ctrl.biometricLogin();
    }
  }

  Future<void> _submit() async {
    await ref
        .read(authControllerProvider.notifier)
        .login(_user.text.trim(), _pass.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [AppColors.gold, Color(0xFFFFCE6B)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('V',
                      style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 30)),
                ),
                const SizedBox(height: 16),
                const Text('Admin de Tienda',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(ApiConfig.displayHost,
                    style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                const SizedBox(height: 28),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'Email o usuario'),
                  autofillHints: const [AutofillHints.username],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    // 눈 아이콘: 입력한 비밀번호가 맞는지 잠깐 확인 (표시/숨김)
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      color: AppColors.dim,
                      tooltip: _obscure
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  // 진단용: 길게 눌러 복사 가능 (전체 오류 노출)
                  SelectableText(state.error!,
                      style: const TextStyle(color: AppColors.red, fontSize: 12)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(state.loading ? 'Ingresando…' : 'Ingresar'),
                    ),
                  ),
                ),
                if (_canBio) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: state.loading
                        ? null
                        : () => ref
                            .read(authControllerProvider.notifier)
                            .biometricLogin(),
                    icon: const Icon(Icons.fingerprint, color: AppColors.gold),
                    label: const Text('Ingresar con huella',
                        style: TextStyle(color: AppColors.gold)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
