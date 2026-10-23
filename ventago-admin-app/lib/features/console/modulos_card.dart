import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

// [2026-10-21 pedido del usuario] «Módulos & setup» deja de ser sólo lectura.
// Qué se puede tocar lo decide el servidor (api admin-console/modulos-tienda.ts):
//   FE = aprobación de superadmin + uso (fe_uso, 2026-10-23: superadmin también lo prende) · VTO · Woo/TiendaNube sólo si la conexión existe · apps del menú
//   (Admin/Venta/Producto/Herramientas fijas; Talleres/M. Prima: prender = prueba nueva de 30 días).
// WhatsApp y App vendedor no tienen interruptor por tienda → quedan con candado.
// Arriba: «Cliente fijo» — confirmado no se suspende por cobro.

class ModuloApp {
  final String slug, nombre;
  final bool enabled, fija, paga;
  final String? billingStatus, trialEndsAt;

  ModuloApp.fromJson(Map<String, dynamic> j)
      : slug = '${j['slug']}',
        nombre = '${j['nombre'] ?? j['slug']}',
        enabled = j['enabled'] == true,
        fija = j['fija'] == true,
        paga = j['paga'] == true,
        billingStatus = j['billingStatus'] as String?,
        trialEndsAt = j['trialEndsAt'] as String?;
}

class ModulosTienda {
  final bool feAprobada, feEnUso, vto;
  final bool wooConfigurado, wooActivo, tnConfigurado, tnActivo;
  final List<ModuloApp> apps;

  ModulosTienda.fromJson(Map<String, dynamic> j)
      : feAprobada = j['fe']?['aprobada'] == true,
        feEnUso = j['fe']?['enUso'] == true,
        vto = j['vto']?['enabled'] == true,
        wooConfigurado = j['woocommerce']?['configurado'] == true,
        wooActivo = j['woocommerce']?['activo'] == true,
        tnConfigurado = j['tiendanube']?['configurado'] == true,
        tnActivo = j['tiendanube']?['activo'] == true,
        apps = ((j['apps'] as List?) ?? const [])
            .map((e) => ModuloApp.fromJson(e as Map<String, dynamic>))
            .toList();
}

final modulosProvider =
    FutureProvider.autoDispose.family<ModulosTienda, int>((ref, storeId) {
  return ref
      .read(consoleRepositoryProvider)
      .getModulos(storeId)
      .then(ModulosTienda.fromJson);
});

String mensajeDeError(Object e) {
  if (e is DioException) {
    final m = e.response?.data is Map ? (e.response!.data as Map)['message'] : null;
    if (m != null) return m is List ? m.join(', ') : '$m';
  }

  return '$e';
}

class ModulosCard extends ConsumerStatefulWidget {
  final Tenant tenant;
  const ModulosCard({super.key, required this.tenant});

  @override
  ConsumerState<ModulosCard> createState() => _ModulosCardState();
}

class _ModulosCardState extends ConsumerState<ModulosCard> {
  String? _guardando; // clave en curso (deshabilita sólo ese interruptor)
  DateTime? _fijoDesde;

  @override
  void initState() {
    super.initState();
    _fijoDesde = widget.tenant.fixedCustomerAt;
  }

  int get _storeId => widget.tenant.storeId;

  Future<bool> _confirmar(String titulo, String texto, String accion) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(accion)),
        ],
      ),
    );

    return ok == true;
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? AppColors.red : AppColors.green,
      content: Text(texto),
    ));
  }

  Future<void> _cambiar(String clave, bool valor, {String? confirmar}) async {
    if (confirmar != null &&
        !await _confirmar(valor ? 'Activar' : 'Desactivar', confirmar,
            valor ? 'Activar' : 'Desactivar')) {
      return;
    }
    setState(() => _guardando = clave);
    try {
      await ref.read(consoleRepositoryProvider).setModulo(_storeId, clave, valor);
      ref.invalidate(modulosProvider(_storeId));
      ref.invalidate(tenantsProvider);
    } catch (e) {
      if (mounted) _aviso('No se pudo cambiar: ${mensajeDeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _guardando = null);
    }
  }

  Future<void> _confirmarFijo() async {
    final ok = await _confirmar(
      'Cliente fijo',
      '¿Confirmar «${widget.tenant.storeName}» como cliente fijo?\n\n'
          'No se suspende por prueba vencida ni por cobro: el cobro lo hacés vos. '
          'Si estaba suspendida por prueba vencida, se reactiva.',
      'Confirmar',
    );
    if (!ok) return;
    setState(() => _guardando = 'fijo');
    try {
      await ref.read(consoleRepositoryProvider).confirmFixedCustomer(_storeId);
      ref.invalidate(tenantsProvider);
      if (mounted) {
        setState(() => _fijoDesde = DateTime.now());
        _aviso('${widget.tenant.storeName} es cliente fijo');
      }
    } catch (e) {
      if (mounted) _aviso('No se pudo confirmar: ${mensajeDeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _guardando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mods = ref.watch(modulosProvider(_storeId));
    final t = widget.tenant;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('MÓDULOS & SETUP',
              style: TextStyle(
                  color: AppColors.dim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7)),
        ),
        _filaFijo(),
        mods.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('No se pudieron leer los módulos: ${mensajeDeError(e)}',
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ),
          data: (m) => Column(children: [
            // [2026-10-23 pedido del usuario] el USO también se cambia desde acá (antes sólo la
            //   aprobación: prenderla dejaba «la tienda aún no la activó»)
            _fila('📄', 'Factura electrónica',
                m.feEnUso
                    ? 'En uso · emite con F10'
                    : (m.feAprobada ? 'Apagada · aprobada' : 'Apagada · prenderla también la aprueba'),
                m.feEnUso, 'fe_uso',
                confirmarApagar: 'La tienda deja de emitir factura electrónica. '
                    'La aprobación queda: la podés volver a prender cuando quieras.'),
            _fila('✅', 'Aprobación FE', m.feAprobada ? 'Aprobada' : 'Sin aprobación', m.feAprobada, 'fe',
                confirmarApagar: 'Quitar la aprobación apaga la factura electrónica de la tienda '
                    '(no podrá emitir hasta volver a aprobarla).'),
            _fila('👗', 'Probador virtual (VTO)', '${t.vtoMonth} VTO/mes', m.vto, 'vto'),
            _filaCanal('🛒', 'WooCommerce', m.wooConfigurado, m.wooActivo, 'woocommerce'),
            _filaCanal('🏬', 'TiendaNube', m.tnConfigurado, m.tnActivo, 'tiendanube'),
            _filaCandado('💬', 'WhatsApp', t.modWhatsapp,
                '${t.whatsappMonth} msg/mes · número común, sin interruptor por tienda'),
            _filaCandado('📱', 'App vendedor', t.modVendedor,
                '${t.vendedorDevices} disp. · se gestiona por dispositivo'),
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('MENÚS',
                    style: TextStyle(
                        color: AppColors.dim,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7)),
              ),
            ),
            ...m.apps.map(_filaApp),
          ]),
        ),
      ]),
    );
  }

  Widget _filaFijo() {
    final desde = _fijoDesde;
    final cargando = _guardando == 'fijo';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1C2A48)))),
      child: Row(children: [
        Icon(desde != null ? Icons.verified : Icons.verified_outlined,
            size: 20, color: desde != null ? AppColors.green : AppColors.dim),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              desde != null
                  ? 'Cliente fijo desde ${DateFormat('dd/MM/yyyy').format(desde.toLocal())} · no se suspende por cobro'
                  : 'Cliente en prueba · se suspende al vencer',
              style: TextStyle(
                  color: desde != null ? AppColors.green : AppColors.dim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
        if (desde == null)
          TextButton(
            onPressed: cargando ? null : _confirmarFijo,
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            child: Text(cargando ? '…' : 'Confirmar fijo',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
      ]),
    );
  }

  Widget _base(String icono, String titulo, String sub, Color colorSub, Widget derecha) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1C2A48)))),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.navy2, borderRadius: BorderRadius.circular(10)),
          child: Text(icono, style: const TextStyle(fontSize: 15)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(color: colorSub, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
        derecha,
      ]),
    );
  }

  Widget _switch(String clave, bool on, {String? confirmarApagar, String? confirmarPrender}) {
    final ocupado = _guardando == clave;

    return ocupado
        ? const SizedBox(
            width: 44,
            height: 26,
            child: Center(
                child: SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
        : Switch(
            value: on,
            activeThumbColor: AppColors.green,
            onChanged: _guardando != null
                ? null
                : (v) => _cambiar(clave, v, confirmar: v ? confirmarPrender : confirmarApagar),
          );
  }

  Widget _fila(String icono, String titulo, String sub, bool on, String clave,
      {String? confirmarApagar}) {
    return _base(icono, titulo, sub, on ? AppColors.green : AppColors.dim,
        _switch(clave, on, confirmarApagar: confirmarApagar));
  }

  Widget _filaCanal(String icono, String titulo, bool configurado, bool activo, String clave) {
    if (!configurado) {
      return _base(icono, titulo, 'Sin conexión · se configura desde la web', AppColors.dim,
          const Icon(Icons.lock_outline, size: 16, color: AppColors.dim));
    }

    return _base(
        icono,
        titulo,
        activo ? 'Conectado' : 'Pausado',
        activo ? AppColors.green : AppColors.amber,
        _switch(clave, activo,
            confirmarApagar: 'Pausar la conexión: los pedidos y la sincronización con la '
                'tienda web dejan de entrar hasta reactivarla.'));
  }

  Widget _filaCandado(String icono, String titulo, bool on, String sub) {
    return _base(icono, titulo, on ? 'Activo · $sub' : 'Inactivo · $sub',
        on ? AppColors.green : AppColors.dim,
        const Icon(Icons.lock_outline, size: 16, color: AppColors.dim));
  }

  Widget _filaApp(ModuloApp a) {
    final iconos = {
      'admin': '⚙️',
      'venta': '🧾',
      'producto': '📦',
      'reportes': '📊',
      'talleres': '🧵',
      'materia-prima': '🧶',
      'herramientas': '🛠️',
    };
    String sub;
    if (!a.enabled) {
      sub = a.billingStatus == 'suspended' ? 'Apagado · prueba vencida' : 'Apagado';
    } else if (a.paga && a.billingStatus == 'trial') {
      final fin = DateTime.tryParse(a.trialEndsAt ?? '');
      sub = fin == null ? 'Prueba' : 'Prueba hasta ${DateFormat('dd/MM').format(fin)}';
    } else if (a.paga && a.billingStatus == 'active') {
      sub = 'Activo · con cobro';
    } else {
      sub = a.fija ? 'Siempre activo' : 'Activo';
    }

    return _base(
        iconos[a.slug] ?? '▫️',
        a.nombre,
        sub,
        a.enabled ? AppColors.green : AppColors.dim,
        a.fija
            ? const Icon(Icons.lock_outline, size: 16, color: AppColors.dim)
            : _switch('app:${a.slug}', a.enabled,
                confirmarPrender: a.paga
                    ? 'Se activa con una prueba nueva de 30 días.'
                    : null,
                confirmarApagar: 'El menú «${a.nombre}» desaparece para todos los usuarios '
                    'de la tienda (al recargar).'));
  }
}
