import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'usuarios_repository.dart';
import 'permissions_editor_screen.dart';
import 'user_form_screen.dart';

// 상단 세그먼트 상태 (0=Usuarios 1=Roles) — 일상적으로 더 자주 보는 Usuarios 가 먼저
final _usuariosTabProvider = StateProvider.autoDispose<int>((ref) => 0);

class UsuariosScreen extends ConsumerWidget {
  const UsuariosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_usuariosTabProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: _Segment(
            value: tab,
            labels: const ['Usuarios', 'Roles'],
            onChanged: (i) => ref.read(_usuariosTabProvider.notifier).state = i,
          ),
        ),
        Expanded(child: tab == 0 ? const _UsersView() : const _RolesView()),
      ],
    );
  }
}

// ── Roles ──

class _RolesView extends ConsumerWidget {
  const _RolesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storeRolesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(storeRolesProvider);
        await ref.read(storeRolesProvider.future);
      },
      child: async.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrList(msg: 'No se pudieron cargar los roles.', detail: '$e'),
        data: (roles) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            const _Hint('Tocá un rol para editar sus permisos.'),
            const SizedBox(height: 10),
            if (roles.isEmpty) const _Empty('Sin roles'),
            for (final r in roles) ...[
              _Card(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PermissionsEditorScreen(role: r),
                  )),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.navy2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Icon(Icons.shield_outlined,
                            size: 18, color: AppColors.gold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('${r.userCount} usuario${r.userCount == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.dim)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.dim),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Usuarios ──

class _UsersView extends ConsumerWidget {
  const _UsersView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storeUsersProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(storeUsersProvider);
        await ref.read(storeUsersProvider.future);
      },
      child: async.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrList(msg: 'No se pudieron cargar los usuarios.', detail: '$e'),
        data: (users) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const UserFormScreen(),
              )),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: AppColors.gold, size: 18),
                    SizedBox(width: 6),
                    Text('Nuevo usuario',
                        style: TextStyle(
                            color: AppColors.gold, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            if (users.isEmpty) const _Empty('Sin usuarios'),
            for (final u in users) ...[
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UserFormScreen(user: u),
                )),
                child: _Card(
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.navy2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Text(
                        u.fullName.isEmpty ? '?' : u.fullName[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.fullName.isEmpty ? (u.username ?? '#${u.id}') : u.fullName,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                          // 로그인 ID(usuario) — 지점에서 로그인 계정을 바로 확인/안내할 수 있게
                          if (u.username != null && u.username!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.badge_outlined,
                                    size: 12, color: AppColors.dim),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    u.username!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final r in u.roles)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: AppColors.gold.withValues(alpha: 0.35)),
                                  ),
                                  child: Text(r.name,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.gold)),
                                ),
                              if (u.email != null && u.email!.isNotEmpty)
                                Text(u.email!,
                                    style: const TextStyle(
                                        fontSize: 10.5, color: AppColors.dim)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _StatusDot(status: u.status),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 공용 소형 위젯 ──

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

class _Segment extends StatelessWidget {
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _Segment(
      {required this.value, required this.labels, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1428),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == i ? AppColors.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: value == i ? AppColors.navy : AppColors.dim)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});
  @override
  Widget build(BuildContext context) {
    final active = status == 'active' || status == 'trial';
    final color = active ? AppColors.green : AppColors.dim;

    return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 11.5, color: AppColors.dim));
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
            child: Text(text, style: const TextStyle(color: AppColors.dim))),
      );
}

class _ErrList extends StatelessWidget {
  final String msg;
  final String detail;
  const _ErrList({required this.msg, required this.detail});
  @override
  Widget build(BuildContext context) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg,
                    style: const TextStyle(
                        color: AppColors.red, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(detail,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.dim, fontSize: 11)),
              ],
            ),
          ),
        ],
      );
}
