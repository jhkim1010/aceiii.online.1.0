import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

class UserPick {
  final int id;
  final String name;
  final String? storeName;

  UserPick.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        name = ((j['name'] ?? '').toString().trim().isEmpty ? '#${j['id']}' : j['name']).toString(),
        storeName = j['storeName'] as String?;
}

class ActivityEvent {
  final String at, kind, text;
  final num? amount;

  ActivityEvent.fromJson(Map<String, dynamic> j)
      : at = (j['at'] ?? '').toString(),
        kind = (j['kind'] ?? '').toString(),
        text = (j['text'] ?? '').toString(),
        amount = j['amount'] as num?;
}

class UserActivity {
  final List<ActivityEvent> events;
  final int sales, expenses, cobros, audits;
  final num revenue;

  UserActivity.fromJson(Map<String, dynamic> j)
      : events = ((j['events'] ?? []) as List).map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>)).toList(),
        sales = (j['summary']?['sales'] ?? 0) as int,
        expenses = (j['summary']?['expenses'] ?? 0) as int,
        cobros = (j['summary']?['cobros'] ?? 0) as int,
        audits = (j['summary']?['audits'] ?? 0) as int,
        revenue = (j['summary']?['revenue'] ?? 0) as num;
}

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository(ref.read(dioClientProvider));
});

class ActivityRepository {
  final Dio _dio;

  ActivityRepository(this._dio);

  Future<List<UserPick>> getUsers() async {
    final res = await _dio.get<List<dynamic>>('/admin-console/users');

    return (res.data ?? []).map((e) => UserPick.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserActivity> getActivity(int userId, String date) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/admin-console/users/$userId/activity',
      queryParameters: {'date': date},
    );

    return UserActivity.fromJson(res.data ?? {});
  }
}

final consoleUsersProvider = FutureProvider.autoDispose<List<UserPick>>((ref) => ref.read(activityRepositoryProvider).getUsers());
