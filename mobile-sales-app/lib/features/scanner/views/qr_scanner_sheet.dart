// QR 스캐너 바텀시트 — Phase 38 딥링크 `/m/stock?s={storeId}&p={parentProductId}` 파싱.
// 스캔 성공 → 시트 닫고 /product/:p 상세(매트릭스) 직행 (D-14 scan-to-detail).
// 비매칭 페이로드는 토스트로 안내(신뢰 경계: QR 페이로드는 untrusted — productId 만 추출,
// 재고는 백엔드 /mobile/stock 가 세션 매장으로 재-scope, T-37-17).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_theme.dart';

// 딥링크 → parentProductId 추출 (매칭 실패 시 null). 순수 함수(단위 테스트 대상).
int? parseStockDeeplink(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) {
    return null;
  }
  // Phase 38 publisher: `${PUBLIC_WEB_URL}/m/stock?s=&p=`
  if (!uri.path.contains('/m/stock')) {
    return null;
  }
  final p = uri.queryParameters['p'];

  return p == null ? null : int.tryParse(p);
}

// 스캐너 바텀시트 표시. 성공 시 상세로 push.
Future<void> showQrScannerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.navy,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _QrScannerSheet(),
  );
}

class _QrScannerSheet extends StatefulWidget {
  const _QrScannerSheet();

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    final productId = parseStockDeeplink(raw);
    if (productId == null) {
      // 비매칭 — 계속 스캔, 1회성 안내
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Código no reconocido')));

      return;
    }
    _handled = true;
    Navigator.of(context).pop();
    context.push('/product/$productId');
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
              'Escaneá la percha',
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
              'Apuntá al código QR de la percha para ver el stock por color y talle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB9B9C6), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
