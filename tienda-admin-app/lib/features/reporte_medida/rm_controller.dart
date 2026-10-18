// Reporte a medida — estado de la pantalla (constructor + resultado comparten este controlador).
// Validación con debounce y una sola ejecución a la vez; sólo la última petición aplica su
// resultado (port de useValidacionPedido / useEjecucionReporte / useGuardadoAbierto / secuencia.ts).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rm_logica.dart';
import 'rm_modelos.dart';
import 'rm_repository.dart';

class GuardadoAbierto {
  final int id;
  final String name;
  final bool shared;
  final bool esMio;
  final String firmaOriginal;
  final bool catalogoCambio;
  const GuardadoAbierto(this.id, this.name, this.shared, this.esMio, this.firmaOriginal, this.catalogoCambio);
}

class Validacion {
  final bool pendiente;
  final bool ok;
  final String? resumenEs;
  final int? filasEstimadas;
  final List<ErrorPedido> errores;
  const Validacion({this.pendiente = true, this.ok = false, this.resumenEs, this.filasEstimadas, this.errores = const []});
}

class RmState {
  final Catalogo? catalogo;
  final Pedido pedido;
  final GuardadoAbierto? abierto;
  final Validacion validacion;
  final ResultadoReporte? resultado;
  final String? firmaEjecutada; // pedido que produjo el resultado (para marcarlo obsoleto)
  final bool desdeGuardado; // el resultado vino de POST /pedidos/:id/ejecutar
  final bool ejecutando;
  final ErrorRm? error;
  final String? avisoEs;
  final bool avisoMargen;

  const RmState({
    this.catalogo,
    this.pedido = Pedido.inicial,
    this.abierto,
    this.validacion = const Validacion(),
    this.resultado,
    this.firmaEjecutada,
    this.desdeGuardado = false,
    this.ejecutando = false,
    this.error,
    this.avisoEs,
    this.avisoMargen = false,
  });

  bool get hayErrores => validacion.errores.isNotEmpty;
  bool get puedeEjecutar => catalogo != null && !hayErrores && !ejecutando && pedido.metrics.isNotEmpty;
  bool get vigente => resultado != null && firmaEjecutada == firmaPedido(pedido);
  bool get cambiosSinGuardar => abierto != null && abierto!.firmaOriginal != firmaPedido(pedido);

  RmState copyWith({
    Catalogo? catalogo,
    Pedido? pedido,
    Object? abierto = _s,
    Validacion? validacion,
    Object? resultado = _s,
    Object? firmaEjecutada = _s,
    bool? desdeGuardado,
    bool? ejecutando,
    Object? error = _s,
    Object? avisoEs = _s,
    bool? avisoMargen,
  }) =>
      RmState(
        catalogo: catalogo ?? this.catalogo,
        pedido: pedido ?? this.pedido,
        abierto: identical(abierto, _s) ? this.abierto : abierto as GuardadoAbierto?,
        validacion: validacion ?? this.validacion,
        resultado: identical(resultado, _s) ? this.resultado : resultado as ResultadoReporte?,
        firmaEjecutada: identical(firmaEjecutada, _s) ? this.firmaEjecutada : firmaEjecutada as String?,
        desdeGuardado: desdeGuardado ?? this.desdeGuardado,
        ejecutando: ejecutando ?? this.ejecutando,
        error: identical(error, _s) ? this.error : error as ErrorRm?,
        avisoEs: identical(avisoEs, _s) ? this.avisoEs : avisoEs as String?,
        avisoMargen: avisoMargen ?? this.avisoMargen,
      );
}

const _s = Object();

final rmControllerProvider =
    StateNotifierProvider.autoDispose<RmController, RmState>((ref) => RmController(ref.read(rmRepositoryProvider)));

class RmController extends StateNotifier<RmState> {
  final RmRepository _repo;
  RmController(this._repo) : super(const RmState());

  Timer? _debounce;
  int _tokenValidacion = 0;
  int _tokenEjecucion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _tokenValidacion++;
    _tokenEjecucion++;
    super.dispose();
  }

  void iniciar(Catalogo c) {
    if (state.catalogo != null) return;
    state = state.copyWith(catalogo: c);
    _validar();
  }

  // Todo cambio del pedido pasa por acá: invalida la validación anterior y programa otra.
  void cambiar(Pedido p, {String? aviso}) {
    // Un cambio también invalida la ejecución en curso: su respuesta es de otro pedido (CODEX P2).
    final cancelada = state.ejecutando;
    if (cancelada) _tokenEjecucion++;
    state = state.copyWith(
        pedido: p, avisoEs: aviso, validacion: const Validacion(), ejecutando: cancelada ? false : null);
    _validar();
  }

  void alternarMetrica(String id) {
    final c = state.catalogo;
    if (c != null) cambiar(alternarMetricaPura(c, state.pedido, id));
  }

  void alternarDimension(String id) {
    final c = state.catalogo;
    if (c == null) return;
    final r = alternarDimensionPura(c, state.pedido, id);
    cambiar(r.pedido, aviso: r.avisoEs);
  }

  void aplicarFix(FixPedido f) => cambiar(state.pedido.aplicarPatch(f.patch));

  void aplicarPlantilla(PlantillaCatalogo t) {
    final c = state.catalogo;
    if (c == null || t.pedido == null) return;
    final q = quitarBloqueadas(c, t.pedido!);
    // Una plantilla empieza un reporte nuevo: deja de ser «el guardado abierto».
    state = state.copyWith(abierto: null, avisoMargen: false);
    cambiar(q.pedido, aviso: q.avisoEs);
    ejecutar();
  }

  void _validar() {
    _debounce?.cancel();
    final token = ++_tokenValidacion; // el token nace con el cambio, no al disparar (P3 CODEX)
    final pedido = state.pedido;
    if (pedido.metrics.isEmpty) {
      state = state.copyWith(
          validacion: Validacion(
              pendiente: false, errores: [ErrorPedido('SIN_METRICAS', 'Elegí al menos una medida en el paso 1.')]));

      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await _repo.validar(pedido);
        if (!mounted || token != _tokenValidacion) return;
        state = state.copyWith(
            validacion: Validacion(
                pendiente: false, ok: r.ok, resumenEs: r.resumenEs, filasEstimadas: r.filasEstimadas, errores: r.errores));
      } catch (e) {
        if (!mounted || token != _tokenValidacion) return;
        final err = clasificarError(e);
        // 400/403 con errores = validación; red/timeout no bloquean: el botón sigue disponible.
        state = state.copyWith(
            validacion: Validacion(pendiente: false, errores: err.tipo == TipoErrorRm.validacion ? err.errores : const []));
      }
    });
  }

  Future<void> ejecutar() async {
    final c = state.catalogo;
    if (c == null || state.ejecutando) return;
    final token = ++_tokenEjecucion;
    final pedido = state.pedido;
    final abierto = state.abierto;
    final usarGuardado = abierto != null && abierto.firmaOriginal == firmaPedido(pedido) && !state.avisoMargen;
    state = state.copyWith(ejecutando: true, error: null);
    try {
      final r = usarGuardado ? await _repo.ejecutarGuardado(abierto.id) : await _repo.ejecutar(pedido);
      if (!mounted || token != _tokenEjecucion) return;
      state = state.copyWith(
          resultado: r, firmaEjecutada: firmaPedido(pedido), desdeGuardado: usarGuardado, ejecutando: false);
    } catch (e) {
      if (!mounted || token != _tokenEjecucion) return;
      state = state.copyWith(error: clasificarError(e), ejecutando: false);
    }
  }

  // Abrir un guardado: carga sus pasos, lo adapta a mis permisos y lo ejecuta.
  Future<void> abrirGuardado(int id) async {
    final c = state.catalogo;
    if (c == null) return;
    final token = ++_tokenEjecucion; // un resultado viejo no puede aparecer bajo el título nuevo
    state = state.copyWith(ejecutando: true, error: null, resultado: null, firmaEjecutada: null);
    try {
      final d = await _repo.guardado(id);
      if (!mounted || token != _tokenEjecucion) return;
      final a = adaptarGuardado(c, d.order);
      final adaptado = firmaPedido(a.pedido) != firmaPedido(d.order);
      state = state.copyWith(
        pedido: a.pedido,
        avisoEs: a.avisoEs,
        avisoMargen: adaptado && d.order.metrics.contains('margen') && !a.pedido.metrics.contains('margen'),
        abierto: GuardadoAbierto(d.id, d.name, d.shared, d.esMio, firmaPedido(a.pedido), d.catalogoCambio),
        validacion: const Validacion(),
        ejecutando: false,
      );
      _validar();
      await ejecutar();
    } catch (e) {
      if (!mounted || token != _tokenEjecucion) return;
      state = state.copyWith(error: clasificarError(e), ejecutando: false);
    }
  }

  void cerrarGuardado() => state = state.copyWith(abierto: null, avisoMargen: false);

  Future<int> guardarNuevo(String name, bool shared) async {
    // La firma es la del pedido ENVIADO: si se cambia algo mientras responde, queda «sin guardar».
    final enviado = state.pedido;
    final id = await _repo.crear(name, shared, enviado);
    if (mounted) {
      state = state.copyWith(
          abierto: GuardadoAbierto(id, name, shared, true, firmaPedido(enviado), false), avisoMargen: false);
    }

    return id;
  }

  Future<void> guardarCambios() async {
    final a = state.abierto;
    if (a == null || !a.esMio) return;
    final enviado = state.pedido;
    await _repo.actualizar(a.id, order: enviado);
    if (mounted) {
      state = state.copyWith(
          abierto: GuardadoAbierto(a.id, a.name, a.shared, a.esMio, firmaPedido(enviado), false));
    }
  }

  Future<CsvDescargado> csv() {
    final a = state.abierto;

    return state.desdeGuardado && a != null ? _repo.csvGuardado(a.id) : _repo.csv(state.pedido);
  }
}

// Alias para no chocar con los métodos del controlador.
Pedido alternarMetricaPura(Catalogo c, Pedido p, String id) => alternarMetrica(c, p, id);
ResultadoQuitar alternarDimensionPura(Catalogo c, Pedido p, String id) => alternarDimension(c, p, id);
