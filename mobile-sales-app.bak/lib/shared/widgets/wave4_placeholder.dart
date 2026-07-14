// Wave 4 placeholder — 판매 화면(S2 Catálogo / S3 Detalle / S4 Comanda / S5 Done)은
// Wave 4 에서 구현. 셸(Wave 3)에서는 라우트 트리 스텁만 존재한다.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class Wave4Placeholder extends StatelessWidget {
  final String title;
  final String subtitle;

  const Wave4Placeholder({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🚧', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
