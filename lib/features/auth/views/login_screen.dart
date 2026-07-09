// S0 Login (/login) — Usuario + PIN(숫자 obscure) + Sucursal 셀렉터 + Ingresar (UI-D3).
// navy 전면 배경, gold 로고/CTA. 에러는 인라인 Alert + prominent 토스트 (es-AR, feedback_error_visibility).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/api_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/scope_provider.dart';
import '../widgets/sucursal_selector.dart';

// 백엔드 에러 코드 → es-AR 카피 매핑 (UI-SPEC §5)
String mapAuthErrorMessage(Object? error) {
  final code = error is ApiException ? error.code : null;
  switch (code) {
    case 'VENDEDOR_SCOPE_NOT_DEFINED':
    case 'RESELLER_SCOPE_NOT_DEFINED':
      return 'Tu sucursal no está configurada. Contactá al administrador.';
    case 'MOBILE_SESSION_EXPIRED':
      return 'Tu sesión se cerró porque ingresaste en otro dispositivo.';
    case 'STORE_SUSPENDED':
      return 'El comercio está suspendido. Contactá al administrador.';
    case 'INVALID_CREDENTIALS':
      return 'Usuario o PIN incorrectos.';
    default:
      return error is ApiException ? error.message : 'No se pudo iniciar sesión.';
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _pinController = TextEditingController();

  // 로그인 화면에서 미리 알 수 있는 지점은 없음(로그인 후 scope 확정) → 서버가 강제
  int? _selectedBranchId;
  String? _inlineError;

  @override
  void dispose() {
    _usuarioController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _inlineError = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();

    await ref.read(scopeNotifierProvider.notifier).login(
          usuario: _usuarioController.text.trim(),
          pin: _pinController.text.trim(),
          selectedBranchId: _selectedBranchId,
        );

    if (!mounted) {
      return;
    }

    final state = ref.read(scopeNotifierProvider);
    if (state.hasError) {
      final msg = mapAuthErrorMessage(state.error);
      setState(() => _inlineError = msg);
      // prominent 토스트 (인라인 Alert 와 이중 노출)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // 성공 시 go_router redirect 가 /home 으로 이동 (별도 네비게이션 불필요)
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(scopeNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // gold 로고 마크
                  Container(
                    height: 72,
                    width: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.gold, AppColors.goldDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('🏷️', style: TextStyle(fontSize: 34)),
                  ),
                  const SizedBox(height: 18),

                  // 타이틀: Ventago Ventas (Ventas = gold)
                  Text.rich(
                    TextSpan(
                      children: const [
                        TextSpan(
                          text: 'Ventago ',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Ventas',
                          style: TextStyle(color: AppColors.gold),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Punto de venta móvil',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  // 서버 URL (읽기전용, 코드 고정)
                  Text(
                    ApiConfig.displayHost,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 32),

                  // 인라인 에러 Alert (feedback_error_visibility)
                  if (_inlineError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.red),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _inlineError!,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Usuario 필드
                  const _WhiteLabel('USUARIO'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _usuarioController,
                    enabled: !isLoading,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'Usuario',
                      prefixIcon: Icon(Icons.person_outline, color: AppColors.muted),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingresá tu usuario' : null,
                  ),
                  const SizedBox(height: 18),

                  // PIN 필드 (숫자, obscure) — UI-D3
                  const _WhiteLabel('PIN DE VENDEDOR'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _pinController,
                    enabled: !isLoading,
                    keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                    obscureText: true,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      hintText: '••••',
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_outline, color: AppColors.muted),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresá tu PIN';
                      }
                      if (v.trim().length < 4) {
                        return 'El PIN debe tener al menos 4 dígitos';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // Sucursal 셀렉터 (로그인 후 scope 로 확정, 여기선 안내 placeholder)
                  SucursalSelector(
                    branchIds: const [],
                    value: _selectedBranchId,
                    onChanged: (id) => setState(() => _selectedBranchId = id),
                  ),
                  const SizedBox(height: 28),

                  // Ingresar (gold CTA)
                  SizedBox(
                    height: 54,
                    child: isLoading
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.gold),
                          )
                        : ElevatedButton(
                            onPressed: _handleLogin,
                            style: AppTheme.goldCtaStyle,
                            child: const Text('Ingresar'),
                          ),
                  ),
                  const SizedBox(height: 18),

                  // hint (mobile_sessions 분리)
                  const Text(
                    '🔒 Sesión móvil independiente de la caja de escritorio',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
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

// navy 배경 위 라벨 (uppercase, 밝은 muted)
class _WhiteLabel extends StatelessWidget {
  final String text;

  const _WhiteLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFFB9B9C6),
          letterSpacing: 0.5,
        ),
      );
}
