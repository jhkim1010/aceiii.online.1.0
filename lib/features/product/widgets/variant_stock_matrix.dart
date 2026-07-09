// S3 매트릭스 위젯 (D-15 port of VariantsStockVenta) — 행=색상, 열=talle.
// 셀: 직접 숫자 입력(NO +/- stepper) + 하단 `mine:N (green/bold) · otras:N (muted)` read-only.
// 색상 컬럼 sticky + talle 가로 스크롤. 상태: sel(gold 보더+amber 배경) / out(dash+비활성) /
// depleted(자지점 소진→입력 비활성). NO over/red, NO traslado 배너 (UI-D2).
//
// 입력은 컨트롤러의 variantQuantities(키 = `colorId-sizeId`, 웹 VariantsStockVenta 와 동일)
// 로 누적되어 cart_provider 로 병합된다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../data/stock_dto.dart';
import '../providers/variant_matrix_provider.dart';

const double _kColW = 108; // 색상 컬럼 너비
const double _kCellW = 82; // talle 셀 너비
const double _kHeadH = 40; // 헤더 높이
const double _kRowH = 84; // 행 높이

class VariantStockMatrix extends StatefulWidget {
  final VariantMatrixController controller;

  const VariantStockMatrix({super.key, required this.controller});

  @override
  State<VariantStockMatrix> createState() => _VariantStockMatrixState();
}

class _VariantStockMatrixState extends State<VariantStockMatrix> {
  // 셀별 TextEditingController (포커스/입력 유지 — 매 rebuild 재생성 방지)
  final Map<String, TextEditingController> _cellCtrls = {};

  @override
  void dispose() {
    for (final c in _cellCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(VariantStock v) {
    final key = VariantMatrixController.keyFor(v);

    return _cellCtrls.putIfAbsent(key, () {
      final qty = widget.controller.qtyFor(v);

      return TextEditingController(text: qty > 0 ? '$qty' : '');
    });
  }

  // 고유 색상/talle (첫 등장 순서 유지, id 기준 중복 제거)
  List<VariantLabel> get _colors => _distinct((v) => v.color);
  List<VariantLabel> get _sizes => _distinct((v) => v.size);

  List<VariantLabel> _distinct(VariantLabel Function(VariantStock) pick) {
    final seen = <int?>{};
    final out = <VariantLabel>[];
    for (final v in widget.controller.variants) {
      final label = pick(v);
      if (!seen.contains(label.id)) {
        seen.add(label.id);
        out.add(label);
      }
    }

    return out;
  }

  VariantStock? _variant(VariantLabel color, VariantLabel size) {
    for (final v in widget.controller.variants) {
      if (v.color.id == color.id && v.size.id == size.id) {
        return v;
      }
    }

    return null;
  }

  void _onCellChanged(VariantStock v, String raw) {
    final parsed = int.tryParse(raw) ?? 0;
    final cap = widget.controller.availableFor(v);
    widget.controller.setQty(v, parsed);
    // 상한 초과 입력 → 클램프 후 필드 텍스트 정정 + 안내 (UI-D2, over 상태 없음)
    if (parsed > cap) {
      final ctrl = _ctrlFor(v);
      final clamped = cap > 0 ? '$cap' : '';
      ctrl.value = TextEditingValue(
        text: clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Sin disponible: máx $cap')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    final sizes = _sizes;

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // sticky 색상 컬럼
          Column(
            children: [
              _headerCell(const SizedBox(width: _kColW), 'Color / Talle'),
              for (final c in colors)
                SizedBox(
                  width: _kColW,
                  height: _kRowH,
                  child: _colorLabel(c),
                ),
            ],
          ),
          // talle 컬럼 가로 스크롤
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // talle 헤더
                  Row(
                    children: [
                      for (final s in sizes)
                        _headerCell(
                          const SizedBox(width: _kCellW),
                          s.name ?? '—',
                        ),
                    ],
                  ),
                  // 색상별 행
                  for (final c in colors)
                    Row(
                      children: [
                        for (final s in sizes)
                          SizedBox(
                            width: _kCellW,
                            height: _kRowH,
                            child: _cell(_variant(c, s)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(Widget sizer, String text) {
    return SizedBox(
      height: _kHeadH,
      child: Stack(
        children: [
          sizer,
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorLabel(VariantLabel c) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.line,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              c.name ?? '—',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(VariantStock? v) {
    if (v == null || v.isOut) {
      // out: 물리 재고 전무 → dash + 비활성
      return const Center(
        child: Text('—', style: TextStyle(color: AppColors.line, fontSize: 18)),
      );
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final qty = widget.controller.qtyFor(v);
        final available = widget.controller.availableFor(v);
        final depleted = available <= 0; // 자지점 소진(타지점만 있음) → 입력 비활성
        final selected = qty > 0;
        final ctrl = _ctrlFor(v);
        // 외부(카트 추가 후 리셋 등)에서 값이 바뀌면 텍스트 동기화
        final want = qty > 0 ? '$qty' : '';
        if (ctrl.text != want && !selected) {
          ctrl.text = want;
        }

        return Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? AppColors.amberSoft : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.line,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 34,
                child: TextField(
                  controller: ctrl,
                  enabled: !depleted,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                    color: selected ? AppColors.green : AppColors.muted,
                    fontFeatures: kTabularFigures,
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (raw) => _onCellChanged(v, raw),
                ),
              ),
              // mine:N (green/bold) · otras:N (muted) — read-only
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${v.stock}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: v.stock > 0 ? AppColors.green : AppColors.muted,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  TextSpan(
                    text: ' · otras:${v.otras}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ],
          ),
        );
      },
    );
  }
}
