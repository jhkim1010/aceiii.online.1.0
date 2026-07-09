// Sucursal 셀렉터 — vendedor 의 scopeBranchIds 에 있는 지점만 노출 (서버 강제, T-37-14).
// 지점이 정확히 1개면 자동선택 + 비활성 (D-10 / UI-D3). 마지막 선택은 secure storage 기억.
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SucursalSelector extends StatelessWidget {
  // 서버가 인가한 지점 id 목록 (scopeBranchIds) — 이 목록만 표시 가능
  final List<int> branchIds;

  // 지점 id → 표시명 (없으면 "Sucursal {id}")
  final Map<int, String>? branchNames;

  // 현재 선택된 지점 id
  final int? value;

  // 선택 변경 콜백
  final ValueChanged<int?> onChanged;

  const SucursalSelector({
    super.key,
    required this.branchIds,
    required this.value,
    required this.onChanged,
    this.branchNames,
  });

  // 지점 1개뿐 → 잠금 (D-10)
  bool get _isLocked => branchIds.length <= 1;

  String _labelFor(int id) => branchNames?[id] ?? 'Sucursal $id';

  @override
  Widget build(BuildContext context) {
    // 지점 정보가 아직 없으면(로그인 전) 안내 placeholder
    if (branchIds.isEmpty) {
      return _lockedField(
        context,
        text: 'Sucursal (se asigna al ingresar)',
        icon: Icons.store_outlined,
      );
    }

    // 정확히 1개 → 자동선택 + 비활성 표시
    if (_isLocked) {
      final only = branchIds.first;

      return _lockedField(
        context,
        text: _labelFor(only),
        icon: Icons.lock_outline,
      );
    }

    // 2개 이상 → 드롭다운
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('SUCURSAL'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: branchIds.contains(value) ? value : null,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.store_outlined, color: AppColors.muted),
          ),
          items: branchIds
              .map((id) => DropdownMenuItem<int>(value: id, child: Text(_labelFor(id))))
              .toList(),
          onChanged: onChanged,
          validator: (v) => v == null ? 'Elegí una sucursal' : null,
        ),
      ],
    );
  }

  // 잠금/placeholder 필드
  Widget _lockedField(BuildContext context, {required String text, required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('SUCURSAL'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.soft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// uppercase 라벨 (UI-SPEC Typography Label)
class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.muted,
          letterSpacing: 0.5,
        ),
      );
}
