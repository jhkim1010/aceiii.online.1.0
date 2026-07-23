import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'activity_repository.dart';

class ActividadScreen extends ConsumerStatefulWidget {
  const ActividadScreen({super.key});

  @override
  ConsumerState<ActividadScreen> createState() => _ActividadScreenState();
}

class _ActividadScreenState extends ConsumerState<ActividadScreen> {
  int? _userId;
  DateTime _date = DateTime.now();
  UserActivity? _activity;
  bool _loading = false;

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _load() async {
    if (_userId == null) return;
    setState(() => _loading = true);
    try {
      final a = await ref.read(activityRepositoryProvider).getActivity(_userId!, _dateStr);
      if (mounted) setState(() => _activity = a);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String kind) => switch (kind) {
        'sale' => Icons.receipt_long,
        'expense' => Icons.payments,
        'box' => Icons.inbox,
        'cobro' => Icons.paid,
        'audit' => Icons.edit,
        'caja_open' => Icons.lock_open,
        'caja_close' => Icons.lock,
        _ => Icons.circle,
      };

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(consoleUsersProvider);
    final fmt = NumberFormat.decimalPattern('es_AR');
    final a = _activity;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Actividad diaria', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        users.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.red)),
          data: (list) => Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _userId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Empleado'),
                  items: list
                      .map((u) => DropdownMenuItem(
                            value: u.id,
                            child: Text('${u.name}${u.storeName != null ? ' · ${u.storeName}' : ''}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _userId = v);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dateStr),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _date = picked);
                    _load();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_userId == null)
          const Text('Seleccioná un empleado.', style: TextStyle(color: AppColors.dim)),
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        if (a != null && !_loading) ...[
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _sum('Ventas', '${a.sales}'),
              _sum('Facturado', '\$${fmt.format(a.revenue)}'),
              _sum('Gastos', '${a.expenses}'),
              _sum('Cobros', '${a.cobros}'),
              _sum('Ediciones', '${a.audits}'),
            ],
          ),
          const SizedBox(height: 12),
          if (a.events.isEmpty)
            const Text('Sin actividad ese día', style: TextStyle(color: AppColors.dim)),
          ...a.events.map((e) => ListTile(
                dense: true,
                leading: Icon(_icon(e.kind), color: AppColors.gold, size: 20),
                title: Text(e.text, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  DateFormat('HH:mm').format(DateTime.tryParse(e.at)?.toLocal() ?? DateTime.now()),
                  style: const TextStyle(color: AppColors.dim, fontSize: 11),
                ),
                trailing: e.amount != null
                    ? Text('\$${fmt.format(e.amount)}', style: const TextStyle(color: AppColors.dim))
                    : null,
              )),
        ],
      ],
    );
  }

  Widget _sum(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: AppColors.dim, fontSize: 10)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ],
    );
  }
}
