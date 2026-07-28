import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'usuarios_repository.dart';

// user == null → 생성, 아니면 수정.
class UserFormScreen extends ConsumerStatefulWidget {
  final StoreUser? user;
  const UserFormScreen({super.key, this.user});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  int? _roleId;
  int? _branchId;
  String _status = 'active';
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    if (u != null) {
      _name.text = u.name;
      _lastName.text = u.lastName;
      _username.text = u.username ?? '';
      _email.text = u.email ?? '';
      _roleId = u.roles.isNotEmpty ? u.roles.first.id : null;
      _status = u.status.isEmpty ? 'active' : u.status;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _username.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final storeId = ref.read(currentStoreIdProvider);
    if (storeId == null) {
      setState(() => _error = 'Sin storeId');

      return;
    }
    // 검증
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');

      return;
    }
    if (!_isEdit) {
      if (_username.text.trim().isEmpty) {
        setState(() => _error = 'El usuario (username) es obligatorio.');

        return;
      }
      if (_pass.text.length < 6) {
        setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');

        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(usuariosRepositoryProvider);
      if (_isEdit) {
        await repo.updateUser(
          widget.user!.id,
          name: _name.text.trim(),
          lastName: _lastName.text.trim(),
          username: _username.text.trim(),
          email: _email.text.trim(),
          password: _pass.text.isEmpty ? null : _pass.text,
          roleId: _roleId,
          branchId: _branchId,
          status: _status,
        );
      } else {
        await repo.createUser(
          name: _name.text.trim(),
          lastName: _lastName.text.trim(),
          username: _username.text.trim(),
          email: _email.text.trim(),
          password: _pass.text,
          roleId: _roleId,
          branchId: _branchId,
          storeId: storeId,
          status: _status,
        );
      }
      if (!mounted) return;
      ref.invalidate(storeUsersProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit ? 'Usuario actualizado.' : 'Usuario creado.'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _extract(e);
      });
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Desactivar usuario'),
        content: Text('¿Desactivar a ${widget.user!.fullName}? '
            'Dejará de aparecer y no podrá iniciar sesión.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.dim))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desactivar',
                  style: TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(usuariosRepositoryProvider).deactivateUser(widget.user!.id);
      if (!mounted) return;
      ref.invalidate(storeUsersProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Usuario desactivado.'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _extract(e);
      });
    }
  }

  // 백엔드가 던진 message(예: 자기 계정 비활성화 차단 403)를 우선 표시.
  String _extract(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }

    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(storeRolesProvider);
    final branchesAsync = ref.watch(branchesProvider);
    // 본인 계정이면 스스로 비활성화/삭제 불가 (로그인 잠김 방지 — 백엔드도 403 으로 차단).
    final currentUserId = ref.watch(authControllerProvider).user?.id;
    final isSelf =
        _isEdit && widget.user?.id != null && widget.user!.id == currentUserId;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Text(_isEdit ? 'Editar usuario' : 'Nuevo usuario',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Guardando…' : 'Guardar',
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _field('Nombre', _name),
          _field('Apellido', _lastName),
          _field('Usuario', _username,
              hint: _isEdit ? null : 'obligatorio'),
          _field('Email', _email, keyboard: TextInputType.emailAddress),
          _field('Contraseña', _pass,
              obscure: true,
              hint: _isEdit ? 'dejar vacío = sin cambio' : 'mín. 6 caracteres'),
          const SizedBox(height: 6),
          _label('Rol'),
          rolesAsync.when(
            loading: () => const _MiniLoad(),
            error: (e, _) => _MiniErr('roles'),
            data: (roles) => _dropdown<int?>(
              value: _roleId,
              items: [
                const DropdownMenuItem(value: null, child: Text('— Sin rol —')),
                for (final r in roles)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => _roleId = v),
            ),
          ),
          const SizedBox(height: 12),
          _label('Sucursal'),
          branchesAsync.when(
            loading: () => const _MiniLoad(),
            error: (e, _) => _MiniErr('sucursales'),
            data: (branches) => _dropdown<int?>(
              value: _branchId,
              items: [
                DropdownMenuItem(
                    value: null,
                    child: Text(_isEdit ? '— Sin cambio —' : '— Sin sucursal —')),
                for (final b in branches)
                  DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
          ),
          const SizedBox(height: 12),
          _label('Estado'),
          _dropdown<String>(
            value: _status,
            // 본인 계정이면 비활성/정지 선택지를 숨긴다(자기 잠금 방지).
            items: [
              const DropdownMenuItem(value: 'active', child: Text('Activo')),
              if (!isSelf)
                const DropdownMenuItem(
                    value: 'inactive', child: Text('Inactivo')),
              if (!isSelf)
                const DropdownMenuItem(
                    value: 'suspended', child: Text('Suspendido')),
              const DropdownMenuItem(value: 'trial', child: Text('Prueba')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'active'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
          if (_isEdit && !isSelf) ...[
            const SizedBox(height: 26),
            TextButton.icon(
              onPressed: _saving ? null : _deactivate,
              icon: const Icon(Icons.person_off_outlined,
                  color: AppColors.red, size: 18),
              label: const Text('Desactivar usuario',
                  style: TextStyle(color: AppColors.red)),
            ),
          ],
          if (isSelf) ...[
            const SizedBox(height: 20),
            const Text('No podés desactivar tu propia cuenta.',
                style: TextStyle(color: AppColors.dim, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {bool obscure = false, String? hint, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: keyboard,
            decoration: InputDecoration(hintText: hint, isDense: true),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
                color: AppColors.dim)),
      );

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1428),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.panel,
          style: const TextStyle(color: AppColors.txt, fontSize: 14),
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.dim),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MiniLoad extends StatelessWidget {
  const _MiniLoad();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
}

class _MiniErr extends StatelessWidget {
  final String what;
  const _MiniErr(this.what);
  @override
  Widget build(BuildContext context) => Text('No se pudo cargar $what',
      style: const TextStyle(color: AppColors.red, fontSize: 11));
}
