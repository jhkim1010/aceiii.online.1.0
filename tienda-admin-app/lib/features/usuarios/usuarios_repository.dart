import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../auth/auth_controller.dart';
import '../../shared/format.dart';

// CRUD 액션 표준 순서.
const kActions = <String>['create', 'read', 'update', 'delete'];

// ── 모델 ──

class RoleRef {
  final int id;
  final String name;
  final String slug;
  RoleRef.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString(),
        slug = (j['slug'] ?? '').toString();
}

class StoreUser {
  final int id;
  final String name;
  final String lastName;
  final String? username;
  final String? email;
  final String status;
  final String? branchName;
  final List<RoleRef> roles;

  StoreUser.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString(),
        lastName = (j['lastName'] ?? '').toString(),
        username = j['username'] as String?,
        email = j['email'] as String?,
        status = (j['status'] ?? '').toString(),
        branchName = (j['branch'] is Map) ? j['branch']['name'] as String? : null,
        roles = ((j['roles'] as List?) ?? const [])
            .map((e) => RoleRef.fromJson(e as Map<String, dynamic>))
            .toList();

  String get fullName => [name, lastName].where((e) => e.isNotEmpty).join(' ').trim();
}

class StoreRole {
  final int id;
  final String name;
  final String slug;
  final int userCount;
  StoreRole.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString(),
        slug = (j['slug'] ?? '').toString(),
        // GET /role?storeId= 는 userRols(오타형) 필드로 사용자 수 반환
        userCount = asInt(j['userRols'] ?? j['userCount']);
}

class PermFunction {
  final int id;
  final String name;
  final String slug;
  final String? resourceKey;
  PermFunction.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString(),
        slug = (j['slug'] ?? '').toString(),
        // JSON 직렬화는 camelCase resourceKey (fallback resource_key)
        resourceKey = (j['resourceKey'] ?? j['resource_key']) as String?;
}

class PermModule {
  final int id;
  final String name;
  final List<PermFunction> functions;
  PermModule.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString(),
        functions = ((j['functions'] as List?) ?? const [])
            .map((e) => PermFunction.fromJson(e as Map<String, dynamic>))
            .toList();
}

class PermApp {
  final int id;
  final String name;
  final List<PermModule> modules;
  PermApp.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString(),
        modules = ((j['modules'] as List?) ?? const [])
            .map((e) => PermModule.fromJson(e as Map<String, dynamic>))
            .toList();
}

// slug 접두사 → CRUD 액션 (groupByResource.ts 이식).
String? inferCrudFromSlug(String slug) {
  if (slug.startsWith('crear-') ||
      slug.startsWith('agregar-') ||
      slug.startsWith('registrar-')) {
    return 'create';
  }
  if (slug.startsWith('editar-') ||
      slug.startsWith('modificar-') ||
      slug.startsWith('cambiar-') ||
      slug.startsWith('restaurar-')) {
    return 'update';
  }
  if (slug.startsWith('eliminar-') || slug.startsWith('borrar-')) {
    return 'delete';
  }
  if (slug.startsWith('ver-') ||
      slug.startsWith('detalle-') ||
      slug.startsWith('reporte-')) {
    return 'read';
  }

  return null;
}

// 한 모듈의 함수들을 Resource 그룹(CRUD)과 Business Action(토글)으로 분리.
class ResourceGroup {
  final String key;
  final String label;
  // 액션별 대상 functionId 목록
  final Map<String, List<int>> crudMap;
  ResourceGroup(this.key, this.label, this.crudMap);
}

class GroupedModule {
  final PermModule module;
  final List<ResourceGroup> resources;
  final List<PermFunction> businessActions;
  GroupedModule(this.module, this.resources, this.businessActions);
}

GroupedModule groupModule(PermModule mod) {
  final resMap = <String, List<PermFunction>>{};
  final business = <PermFunction>[];
  for (final fn in mod.functions) {
    final key = fn.resourceKey;
    if (key != null && key.isNotEmpty) {
      resMap.putIfAbsent(key, () => []).add(fn);
    } else {
      business.add(fn);
    }
  }
  final resources = resMap.entries.map((e) {
    final crud = <String, List<int>>{
      'create': [],
      'read': [],
      'update': [],
      'delete': [],
    };
    for (final fn in e.value) {
      final action = inferCrudFromSlug(fn.slug) ?? 'read';
      crud[action]!.add(fn.id);
    }
    // 라벨 = key 마지막 세그먼트, 구분자 공백, 첫 글자 대문자
    final seg = e.key.split('.').last.replaceAll(RegExp(r'[_-]'), ' ');
    final label = seg.isEmpty
        ? e.key
        : '${seg[0].toUpperCase()}${seg.substring(1)}';

    return ResourceGroup(e.key, label, crud);
  }).toList();

  return GroupedModule(mod, resources, business);
}

// ── 리포지토리 ──

final usuariosRepositoryProvider = Provider<UsuariosRepository>((ref) {
  return UsuariosRepository(ref.read(dioClientProvider));
});

class UsuariosRepository {
  final Dio _dio;
  UsuariosRepository(this._dio);

  Future<List<StoreUser>> getUsers(int storeId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/users/store/$storeId',
      queryParameters: {'page': 0, 'pageSize': 200},
    );
    final list = (res.data?['data'] as List?) ?? const [];

    return list
        .map((e) => StoreUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StoreRole>> getRoles(int storeId) async {
    final res = await _dio.get<List<dynamic>>(
      '/role',
      queryParameters: {'storeId': storeId},
    );

    return (res.data ?? const [])
        .map((e) => StoreRole.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PermApp>> getStructure() async {
    final res = await _dio.get<List<dynamic>>('/functions/structure');

    return (res.data ?? const [])
        .map((e) => PermApp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 역할의 현재 권한 → {functionId: {actions}}.
  Future<Map<int, Set<String>>> getRoleFunctions(int roleId) async {
    final res = await _dio.get<List<dynamic>>('/role-functions/$roleId');
    final map = <int, Set<String>>{};
    for (final e in res.data ?? const []) {
      final rf = e as Map<String, dynamic>;
      final fid = asInt(rf['functionId']);
      final acts = ((rf['roleFunctionActions'] as List?) ?? const [])
          .map((a) => (a as Map)['action'].toString())
          .toSet();
      map[fid] = acts;
    }

    return map;
  }

  // 전체 교체 저장: actions 가 있는 functionId 만 보내면, 빠진 것은 서버가 삭제.
  Future<void> saveBulkActions(
      int roleId, Map<int, Set<String>> functionActions) async {
    final data = functionActions.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => {'functionId': e.key, 'actions': e.value.toList()})
        .toList();
    await _dio.put<dynamic>(
      '/role-functions/bulk-actions/$roleId',
      data: {'data': data},
    );
  }
}

// ── Providers ──

final storeUsersProvider =
    FutureProvider.autoDispose<List<StoreUser>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return ref.read(usuariosRepositoryProvider).getUsers(storeId);
});

final storeRolesProvider =
    FutureProvider.autoDispose<List<StoreRole>>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return ref.read(usuariosRepositoryProvider).getRoles(storeId);
});

final permStructureProvider =
    FutureProvider.autoDispose<List<PermApp>>((ref) {
  return ref.read(usuariosRepositoryProvider).getStructure();
});

final roleFunctionsProvider = FutureProvider.autoDispose
    .family<Map<int, Set<String>>, int>((ref, roleId) {
  return ref.read(usuariosRepositoryProvider).getRoleFunctions(roleId);
});
