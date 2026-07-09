// Ventago 테마 — UI-SPEC §2 디자인 토큰(다크 네이비 + 골드).
// sketch-findings-ace-online / storefront-mockup / despacho-app 와 동일 토큰.
import 'package:flutter/material.dart';

// 디자인 토큰 상수 (목업 :root 그대로)
class AppColors {
  static const navy = Color(0xFF1a1a2e); // 앱바, 로그인 배경, primary 버튼/hero
  static const navy2 = Color(0xFF0f0f1e); // gold 버튼 위 텍스트, 토스트 배경
  static const gold = Color(0xFFf5a623); // accent — CTA/chip/QR/활성강조
  static const goldDark = Color(0xFFb9760f); // gold 그라디언트 끝, reserva 텍스트
  static const ink = Color(0xFF1c1c28); // 기본 텍스트
  static const muted = Color(0xFF6b6b76); // 보조 텍스트, placeholder
  static const soft = Color(0xFFf6f6f8); // 카드/썸네일 배경
  static const line = Color(0xFFe7e7ec); // 보더, 구분선
  static const green = Color(0xFF1d9e75); // 재고 OK pill, 완료 링
  static const greenSoft = Color(0xFFe7f6f0); // 자지점 재고 강조 배경
  static const red = Color(0xFFe24b4a); // 파괴적 액션/에러
  static const amberSoft = Color(0xFFfdf1dd); // low stock pill, 선택 셀 배경
  static const bg = Color(0xFFffffff); // 화면 배경
}

// 숫자(가격/재고/수량)에 적용할 tabular figures TextStyle 헬퍼
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

class AppTheme {
  // Ventago 밝은 배경 + navy/gold accent 테마
  static ThemeData get light {
    final scheme = const ColorScheme.light(
      primary: AppColors.navy,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: AppColors.navy2,
      surface: AppColors.bg,
      onSurface: AppColors.ink,
      error: AppColors.red,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      // 앱바 = navy (S1~S5 공통 상단 바)
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: AppColors.line,
      // 입력 필드 (Usuario / PIN)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.soft,
        hintStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 2),
        ),
      ),
      // 기본 ElevatedButton = navy solid
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.navy2,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // gold 그라디언트 CTA 버튼 스타일 (Caja 전송 등 최대 강조 — accent 예약)
  static ButtonStyle get goldCtaStyle => ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navy2,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      );
}
