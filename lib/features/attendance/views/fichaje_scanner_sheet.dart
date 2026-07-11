// Fichaje 스캐너 바텀시트 — caja 데스크톱 일일 QR `/m/fichaje?s=&b=&d=&t=` 파싱(37-06).
// 스캔 성공 → POST /attendance/punch → /fichaje/result 로 결과 전달. 실패 → es-AR 토스트 후 계속 스캔.
// 신뢰 경계: QR 페이로드는 untrusted — s/b/d/t 만 추출, 백엔드가 HMAC + date freshness 재검증(T-37-31).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/attendance_dto.dart';
import '../providers/attendance_provider.dart';

// 딥링크 → FichajeQr 추출 (매칭 실패 시 null). 순수 함수(단위 테스트 대상).
// `/m/fichaje?s={storeId}&b={branchId}&d={yyyy-mm-dd}&t={token}` — s/b 는 int, d/t 는 필수.
FichajeQr? parseFichajeDeeplink(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) {
    return null;
  }
  // caja publisher: `${PUBLIC_WEB_URL}/m/fichaje?s=&b=&d=&t=`
  if (!uri.path.contains('/m/fichaje')) {
    return null;
  }
  final s = int.tryParse(uri.queryParameters['s'] ?? '');
  final b = int.tryParse(uri.queryParameters['b'] ?? '');
  final d = uri.queryParameters['d'];
  final t = uri.queryParameters['t'];
  // 모든 파라미터 필수 — 하나라도 없으면 null(위조/불완전 QR 방어).
  if (s == null || b == null || d == null || d.isEmpty || t == null || t.isEmpty) {
    return null;
  }

  return FichajeQr(s: s, b: b, d: d, t: t);
}

// 백엔드 에러 코드 → es-AR 토스트 카피 (스펙 §모바일 앱 L144-147).
String fichajeErrorCopy(String? code) {
  switch (code) {
    case 'QR_EXPIRED':
      return 'Pedí el QR de hoy';
    case 'QR_OTHER_STORE':
      return 'QR de otra tienda';
    case 'RESELLER_NOT_APPROVED':
      return 'Tienda no aprobada por admin';
    case 'QR_INVALID':
      return 'QR inválido';
    case 'NOT_A_SELLER':
      return 'No autorizado para fichar';
    default:
      return 'No se pudo registrar. Intentá de nuevo.';
  }
}

// /fichaje 라우트 진입점 — 화면 오픈 즉시 스캐너 시트를 띄운다(딥링크/직접 진입 보조).
// 홈 버튼은 showFichajeScannerSheet 를 직접 호출하므로 이 화면은 라우트용 얇은 래퍼.
class FichajeEntryScreen extends StatefulWidget {
  const FichajeEntryScreen({super.key});

  @override
  State<FichajeEntryScreen> createState() => _FichajeEntryScreenState();
}

class _FichajeEntryScreenState extends State<FichajeEntryScreen> {
  @override
  void initState() {
    super.initState();
    // 첫 프레임 후 시트 오픈(빌드 중 네비게이션 방지).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showFichajeScannerSheet(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
    );
  }
}

// 스캐너 바텀시트 표시. 성공 시 /fichaje/result 로 push.
Future<void> showFichajeScannerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.navy,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _FichajeScannerSheet(),
  );
}

class _FichajeScannerSheet extends ConsumerStatefulWidget {
  const _FichajeScannerSheet();

  @override
  ConsumerState<_FichajeScannerSheet> createState() => _FichajeScannerSheetState();
}

class _FichajeScannerSheetState extends ConsumerState<_FichajeScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    final qr = parseFichajeDeeplink(raw);
    if (qr == null) {
      // 비매칭 — 계속 스캔, 1회성 안내
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Código no reconocido')));

      return;
    }
    // 한 번만 처리 — 더블탭/연속 프레임 멱등(백엔드도 60s 가드).
    _handled = true;
    try {
      final result = await ref.read(punchControllerProvider.notifier).punch(qr);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      context.push('/fichaje/result', extra: result);
    } on ApiException catch (e) {
      // 에러 코드 → es-AR 토스트 후 재스캔 허용.
      if (!mounted) {
        return;
      }
      _handled = false;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(fichajeErrorCopy(e.code))));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _handled = false;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(fichajeErrorCopy(null))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Escaneá el QR de fichaje',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                // 뷰파인더 코너 가이드 (gold)
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.gold, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Text(
              'Apuntá al QR de fichaje que muestra la caja para registrar tu entrada o salida.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9B9C6), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
