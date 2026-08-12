import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'codigo_madre_repository.dart';
import 'codigo_madre_editor_screen.dart';

// Códigos madre — 부모 상품을 찾아 **마스터 정보**(이름 / 가격 / 공개몰 게시)를 편집한다.
// 재고(색×사이즈 수량)는 이 앱에서 다루지 않는다 — 웹 ProductsView 담당.
class CodigoMadreScreen extends ConsumerStatefulWidget {
  const CodigoMadreScreen({super.key});

  @override
  ConsumerState<CodigoMadreScreen> createState() => _CodigoMadreScreenState();
}

class _CodigoMadreScreenState extends ConsumerState<CodigoMadreScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // 타이핑마다 조회하면 목록 API 를 초당 여러 번 때린다 — 350ms 로 묶는다.
  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(madreParentsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: const Text('Códigos madre',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              style: const TextStyle(fontSize: 14, color: AppColors.txt),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o SKU',
                hintStyle: const TextStyle(color: AppColors.dim, fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.dim),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppColors.dim),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
                filled: true,
                fillColor: AppColors.panel,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(madreParentsProvider(_query)),
              child: async.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : async.hasError
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No se pudo cargar la lista.\n${async.error}',
                              style: const TextStyle(
                                  color: AppColors.red, fontSize: 12),
                            ),
                          )
                        ])
                      : _list(async.value ?? const []),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<MadreParent> rows) {
    if (rows.isEmpty) {
      return ListView(children: const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sin resultados',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.dim, fontSize: 13)),
        )
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ParentTile(parent: rows[i]),
    );
  }
}

class _ParentTile extends StatelessWidget {
  final MadreParent parent;
  const _ParentTile({required this.parent});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        // 목록 응답이 이미 이름·가격·게시여부를 다 싣고 온다 — 편집 화면에서 재조회하지 않는다.
        builder: (_) => CodigoMadreEditorScreen(parent: parent),
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parent.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(parent.sku,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.dim,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            // 공개몰 게시 여부 — 목록에서 바로 보이지 않으면 하나씩 열어봐야 한다.
            if (parent.isPublishedShop)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.navy2,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.gold),
                ),
                child: const Text('WEB',
                    style: TextStyle(
                        fontSize: 9,
                        color: AppColors.gold,
                        fontWeight: FontWeight.w800)),
              ),
            if (parent.variantCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.navy2,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text('${parent.variantCount} var.',
                    style: const TextStyle(fontSize: 10, color: AppColors.dim)),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.dim),
          ],
        ),
      ),
    );
  }
}
