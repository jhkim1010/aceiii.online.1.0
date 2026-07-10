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

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(authControllerProvider.notifier).login(_user.text.trim(), _pass.text);
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
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [AppColors.gold, Color(0xFFFFCE6B)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text('V',
                      style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 26)),
                ),
                const SizedBox(height: 16),
                const Text('Ventago Admin',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('superadmin · ${ApiConfig.displayHost}',
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
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  onSubmitted: (_) => _submit(),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(state.error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
