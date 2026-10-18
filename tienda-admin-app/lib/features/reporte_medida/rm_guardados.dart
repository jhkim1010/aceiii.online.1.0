// Reporte a medida — reportes guardados: hoja «Guardar», franja del guardado abierto y «Mis reportes».
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'rm_controller.dart';
import 'rm_logica.dart';
import 'rm_modelos.dart';
import 'rm_repository.dart';
import 'rm_widgets.dart';

void _toast(BuildContext context, String texto, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: error ? const Color(0xFFE24B4A) : null,
    behavior: SnackBarBehavior.floating,
  ));
}

// ── Guardar (nuevo o «Guardar como…») ──
Future<void> mostrarGuardar(BuildContext context, WidgetRef ref, {String? nombreInicial}) async {
  final st = ref.read(rmControllerProvider);
  final c = st.catalogo;
  if (c == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => _GuardarSheet(nombreInicial: nombreInicial ?? nombreSugerido(st.pedido, c)),
  );
}

class _GuardarSheet extends ConsumerStatefulWidget {
  final String nombreInicial;
  const _GuardarSheet({required this.nombreInicial});

  @override
  ConsumerState<_GuardarSheet> createState() => _GuardarSheetState();
}

class _GuardarSheetState extends ConsumerState<_GuardarSheet> {
  late final _nombre = TextEditingController(text: widget.nombreInicial);
  bool _compartir = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Poné un nombre.');

      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(rmControllerProvider.notifier).guardarNuevo(nombre, _compartir);
      ref.invalidate(rmGuardadosProvider);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Guardado en «Mis reportes»: un clic lo vuelve a ejecutar con las fechas del día.');
    } catch (e) {
      setState(() {
        _guardando = false;
        _error = clasificarError(e).mensajeEs;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo!;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Guardar reporte', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(queMuestra(st.pedido, c), style: const TextStyle(fontSize: 12, color: AppColors.dim)),
            const SizedBox(height: 14),
            TextField(
              controller: _nombre,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(labelText: 'Nombre del reporte', errorText: _error),
            ),
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                  color: AppColors.navy2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
              child: SwitchListTile(
                value: _compartir,
                activeThumbColor: AppColors.gold,
                onChanged: (v) => setState(() => _compartir = v),
                title: const Text('Compartir con la tienda', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Lo puede ejecutar cualquiera que tenga el permiso de este menú. Siempre se revisa con los permisos de quien lo abre.',
                    style: TextStyle(fontSize: 12, color: AppColors.dim)),
              ),
            ),
            const SizedBox(height: 6),
            Text(_compartir ? 'Encendido: lo ve la tienda.' : 'Apagado: sólo lo ves vos.',
                style: const TextStyle(fontSize: 12, color: AppColors.dim)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _guardando ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar reporte', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Franja «Estás viendo «…»» ──
class FranjaGuardado extends ConsumerWidget {
  const FranjaGuardado({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rmControllerProvider);
    final a = st.abierto;
    if (a == null) return const SizedBox.shrink();
    final ctrl = ref.read(rmControllerProvider.notifier);
    final cambios = st.cambiosSinGuardar;

    Future<void> guardarCambios() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Guardar cambios'),
          content: Text('Vas a reemplazar «${a.name}». Si querés conservar el original, usá Guardar como….'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar cambios')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await ctrl.guardarCambios();
        ref.invalidate(rmGuardadosProvider);
        if (context.mounted) _toast(context, 'Cambios guardados en «${a.name}».');
      } catch (e) {
        if (context.mounted) _toast(context, clasificarError(e).mensajeEs, error: true);
      }
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: AppColors.navy2, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Estás viendo '),
                TextSpan(text: '«${a.name}»', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (cambios) const TextSpan(text: ' · cambios sin guardar', style: TextStyle(color: AppColors.gold, fontSize: 11)),
              ]),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar el guardado',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: AppColors.dim),
            onPressed: ctrl.cerrarGuardado,
          ),
        ]),
        if (a.catalogoCambio)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: RmAviso.dorado(
                'La definición de alguna medida cambió. El reporte guardado no se modifica: se calcula con la definición actual.'),
          ),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (a.esMio && cambios)
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold, side: const BorderSide(color: AppColors.gold)),
              onPressed: guardarCambios,
              child: const Text('Guardar cambios', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          OutlinedButton(
            onPressed: () => mostrarGuardar(context, ref, nombreInicial: nombreCopia(a.name)),
            child: const Text('Guardar como…', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ]),
    );
  }
}

// ── Mis reportes ──
class MisReportesScreen extends ConsumerStatefulWidget {
  final void Function(int id) onAbrir;
  const MisReportesScreen({super.key, required this.onAbrir});

  @override
  ConsumerState<MisReportesScreen> createState() => _MisReportesScreenState();
}

class _MisReportesScreenState extends ConsumerState<MisReportesScreen> {
  List<GuardadoListado>? _orden; // orden optimista mientras se guarda
  final _entendidos = <int>{};

  Future<void> _reordenar(List<GuardadoListado> lista, int de, int a) async {
    final nueva = [...lista];
    final item = nueva.removeAt(de);
    nueva.insert(a, item); // `a` = índice final (ya ajustado)
    setState(() => _orden = nueva);
    try {
      await ref.read(rmRepositoryProvider).reordenar(nueva.where((g) => g.esMio).map((g) => g.id).toList());
      ref.invalidate(rmGuardadosProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _orden = null); // rollback
      _toast(context, clasificarError(e).mensajeEs, error: true);
    }
  }

  Future<void> _acciones(GuardadoListado g, List<GuardadoListado> lista) async {
    final repo = ref.read(rmRepositoryProvider);
    final i = lista.indexOf(g);
    final accion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(g.name, style: const TextStyle(color: AppColors.dim))),
          ),
          ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Ejecutar'), onTap: () => Navigator.pop(ctx, 'ejecutar')),
          if (g.esMio) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Renombrar'), onTap: () => Navigator.pop(ctx, 'renombrar')),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Guardar como…'), onTap: () => Navigator.pop(ctx, 'copia')),
          if (g.esMio)
            ListTile(
              leading: Icon(g.shared ? Icons.person_outline : Icons.groups_outlined),
              title: Text(g.shared ? 'Dejar de compartir' : 'Compartir con la tienda'),
              onTap: () => Navigator.pop(ctx, 'compartir'),
            ),
          if (g.esMio && i > 0) ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('Subir en la lista'), onTap: () => Navigator.pop(ctx, 'subir')),
          if (g.esMio && i < lista.length - 1)
            ListTile(leading: const Icon(Icons.arrow_downward), title: const Text('Bajar en la lista'), onTap: () => Navigator.pop(ctx, 'bajar')),
          if (g.esMio)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: rmErrorTxt),
              title: const Text('Eliminar…', style: TextStyle(color: rmErrorTxt)),
              onTap: () => Navigator.pop(ctx, 'eliminar'),
            ),
        ]),
      ),
    );
    if (accion == null || !mounted) return;

    try {
      switch (accion) {
        case 'ejecutar':
          widget.onAbrir(g.id);
        case 'renombrar':
          final nombre = await _pedirNombre('Renombrar', g.name);
          if (nombre == null) return;
          await repo.actualizar(g.id, name: nombre);
        case 'copia':
          final nombre = await _pedirNombre('Guardar como…', nombreCopia(g.name));
          if (nombre == null) return;
          final d = await repo.guardado(g.id);
          await repo.crear(nombre, false, d.order);
          if (mounted) _toast(context, 'Guardado en «Mis reportes».');
        case 'compartir':
          await repo.actualizar(g.id, shared: !g.shared);
        case 'subir':
          await _reordenar(lista, i, i - 1);

          return;
        case 'bajar':
          await _reordenar(lista, i, i + 1);

          return;
        case 'eliminar':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Eliminar «${g.name}»'),
              content: Text('Se borra el reporte guardado${g.shared ? ' y deja de verlo la tienda' : ''}. '
                  'Esta acción no se puede deshacer.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Eliminar reporte'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await repo.eliminar(g.id);
      }
      ref.invalidate(rmGuardadosProvider);
    } catch (e) {
      if (mounted) _toast(context, clasificarError(e).mensajeEs, error: true);
    }
  }

  Future<String?> _pedirNombre(String titulo, String inicial) {
    final ctl = TextEditingController(text: inicial);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(controller: ctl, autofocus: true, maxLength: 120, decoration: const InputDecoration(labelText: 'Nombre del reporte')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final t = ctl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asy = ref.watch(rmGuardadosProvider);
    final cat = ref.watch(rmCatalogoProvider).valueOrNull;
    ref.listen(rmGuardadosProvider, (_, _) => setState(() => _orden = null));

    return Scaffold(
      appBar: AppBar(title: const Text('Mis reportes')),
      body: asy.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(clasificarError(e).mensajeEs, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => ref.invalidate(rmGuardadosProvider), child: const Text('Reintentar')),
          ]),
        ),
        data: (datos) {
          final lista = _orden ?? datos;
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Todavía no guardaste ningún reporte. Armá uno y tocá Guardar… para volver a verlo con un clic.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.dim)),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(rmGuardadosProvider),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              buildDefaultDragHandles: false,
              header: const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Mantené apretado ⠿ y arrastrá para ordenar los tuyos.',
                    style: TextStyle(fontSize: 11, color: AppColors.dim)),
              ),
              footer: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Al abrir un reporte guardado se vuelve a validar con los permisos de quien lo abre. '
                    'Los períodos como «este mes» se calculan el día que lo ejecutás.',
                    style: TextStyle(fontSize: 11, color: AppColors.dim, height: 1.4)),
              ),
              itemCount: lista.length,
              onReorderItem: (de, a) {
                if (!lista[de].esMio) return;
                _reordenar(lista, de, a);
              },
              itemBuilder: (_, i) {
                final g = lista[i];

                return Padding(
                  key: ValueKey(g.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FilaGuardado(
                    g: g,
                    index: i,
                    queMuestra: queMuestra(g.order, cat),
                    avisoCambio: g.catalogoCambio && !_entendidos.contains(g.id),
                    onEntendido: () => setState(() => _entendidos.add(g.id)),
                    onEjecutar: () => widget.onAbrir(g.id),
                    onMas: () => _acciones(g, lista),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FilaGuardado extends StatelessWidget {
  final GuardadoListado g;
  final int index;
  final String queMuestra;
  final bool avisoCambio;
  final VoidCallback onEntendido;
  final VoidCallback onEjecutar;
  final VoidCallback onMas;
  const _FilaGuardado(
      {required this.g,
      required this.index,
      required this.queMuestra,
      required this.avisoCambio,
      required this.onEntendido,
      required this.onEjecutar,
      required this.onMas});

  Widget _etiqueta(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: c.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(4)),
        child: Text(t, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: g.catalogoCambio ? AppColors.gold.withValues(alpha: 0.5) : AppColors.line),
      ),
      child: Column(children: [
        Row(children: [
          g.esMio
              ? ReorderableDelayedDragStartListener(
                  index: index,
                  child: const SizedBox(width: 32, height: 44, child: Icon(Icons.drag_indicator, color: rmOff, size: 20)),
                )
              : const SizedBox(width: 32),
          Expanded(
            child: InkWell(
              onTap: onEjecutar,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: g.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (!g.esMio && g.autorNombre != null)
                    TextSpan(text: '  de ${g.autorNombre}', style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                ])),
                const SizedBox(height: 2),
                Text(queMuestra, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  g.shared ? _etiqueta('con la tienda', AppColors.cyan) : _etiqueta('sólo yo', AppColors.dim),
                  g.catalogoCambio ? _etiqueta('definición cambió', AppColors.gold) : _etiqueta('vigente', rmOk),
                ]),
              ]),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
            onPressed: onEjecutar,
            child: const Text('Ejecutar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: 'Más acciones', icon: const Icon(Icons.more_vert, color: AppColors.dim), onPressed: onMas),
        ]),
        if (avisoCambio)
          Container(
            margin: const EdgeInsets.fromLTRB(32, 8, 8, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.navy2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.gold.withValues(alpha: 0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Los números de meses anteriores pueden bajar respecto de lo que viste antes. '
                  'El reporte guardado no se modifica: se calcula con la definición actual.',
                  style: TextStyle(fontSize: 12, color: AppColors.dim, height: 1.4)),
              TextButton(onPressed: onEntendido, child: const Text('Entendido')),
            ]),
          ),
      ]),
    );
  }
}
