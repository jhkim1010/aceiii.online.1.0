import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'afip_modo_repository.dart';

// [2026-09-30] superadmin 이 매장을 `ws` ↔ `soap` 으로 돌리는 화면.
// 웹 `AfipModoCard.tsx` 와 같은 규칙을 따른다:
//
// ★★★ 미리보기 없이 실행할 수 없다. 미리보기에서 받은 `estadoVisto` 를 되돌려
//   보내야 서버가 적용한다 — 그 사이 남이 바꿨으면 거절된다.
// ★★ 전환은 provider · production · 그 매장 모든 발행자의 환경을 서버가
//   한 트랜잭션에서 함께 쓴다. 앱은 부분 적용 선택지를 만들지 않는다.
// ★ 환경(Producción/Homologación)은 SOAP 에서만 고른다 — 게이트웨이는 항상 운영 발급.
class AfipModoScreen extends ConsumerStatefulWidget {
  final int storeId;
  final String storeName;
  const AfipModoScreen({super.key, required this.storeId, required this.storeName});

  @override
  ConsumerState<AfipModoScreen> createState() => _AfipModoScreenState();
}

class _AfipModoScreenState extends ConsumerState<AfipModoScreen> {
  String _destino = 'soap';
  String _entorno = 'prod';
  AfipModoPreview? _preview;
  bool _cargando = true;
  bool _aplicando = false;
  String? _error;

  // 늦게 도착한 옛 미리보기가 새 선택을 덮지 않도록 요청 번호로 거른다.
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String get _entornoEfectivo => _destino == 'ws' ? 'prod' : _entorno;

  Future<void> _cargar() async {
    final my = ++_req;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final p = await ref
          .read(afipModoRepositoryProvider)
          .preview(widget.storeId, _destino, _entornoEfectivo);
      if (!mounted || my != _req) return;
      setState(() => _preview = p);
    } catch (e) {
      if (!mounted || my != _req) return;
      setState(() {
        _preview = null;
        _error = afipErrorMessage(e, 'No pudimos leer la configuración AFIP de esta tienda.');
      });
    } finally {
      if (mounted && my == _req) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmar() async {
    final p = _preview;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Cambiar modo AFIP'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.actual.label}\n→ ${p.destino.label}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
              'Cambia el modo de ${p.emisores.length} emisor(es) de esta tienda al mismo tiempo. '
              'Los comprobantes que se emitan después salen por el nuevo camino.',
              style: const TextStyle(color: AppColors.amber, fontSize: 12.5)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold, foregroundColor: AppColors.navy),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _aplicando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // ★ 미리보기에서 받은 지문을 그대로 되돌려 보낸다.
      final r = await ref.read(afipModoRepositoryProvider).aplicar(
            widget.storeId,
            destino: _destino,
            entorno: _entornoEfectivo,
            estadoVisto: p.estadoVisto,
          );
      if (!mounted) return;
      setState(() => _preview = r);
      messenger.showSnackBar(const SnackBar(
        backgroundColor: AppColors.green,
        content: Text('Modo AFIP actualizado.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.red,
        content: Text(afipErrorMessage(e, 'No pudimos cambiar el modo.')),
      ));

      // 지문이 어긋났을 수 있다 — 다시 읽어 최신 상태를 보여 준다.
      if (mounted) _cargar();
    } finally {
      if (mounted) setState(() => _aplicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: Text('Modo AFIP · ${widget.storeName}'),
        backgroundColor: AppColors.navy2,
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            _selectorCard(),
            if (_cargando && _preview == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_preview == null)
              _aviso(_error ?? 'Sin datos.', AppColors.red)
            else
              ..._detalle(_preview!),
          ],
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _lbl(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: AppColors.dim,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7)),
      );

  Widget _opcion(String label, String sub, bool on, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null && !on ? 0.4 : 1,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.gold.withOpacity(0.16) : AppColors.navy2,
              border: Border.all(color: on ? AppColors.gold : AppColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: on ? AppColors.gold : AppColors.txt,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.dim, fontSize: 10)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _selectorCard() {
    final bloqueado = _aplicando;
    final p = _preview;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl('Modo actual'),
      Text(p?.actual.label ?? '—',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      _lbl('Cambiar a'),
      Row(children: [
        _opcion('Gateway', 'cool-invoice', _destino == 'ws',
            bloqueado ? null : () => _elegir(destino: 'ws')),
        _opcion('ARCA directo', 'SOAP', _destino == 'soap',
            bloqueado ? null : () => _elegir(destino: 'soap')),
      ]),
      const SizedBox(height: 12),
      _lbl('Entorno'),
      // ★ 게이트웨이는 우리가 보내는 값을 무시하고 항상 운영 발급한다.
      //   고르게 두면 화면이 거짓말을 한다 → ws 에서는 잠근다.
      Row(children: [
        _opcion('Producción', 'validez fiscal', _entornoEfectivo == 'prod',
            bloqueado || _destino == 'ws' ? null : () => _elegir(entorno: 'prod')),
        _opcion('Homologación', 'sin validez fiscal', _entornoEfectivo == 'homo',
            bloqueado || _destino == 'ws' ? null : () => _elegir(entorno: 'homo')),
      ]),
      const SizedBox(height: 6),
      Text(
          _destino == 'ws'
              ? 'El gateway emite siempre en producción.'
              : 'Homologación: los comprobantes NO tienen validez fiscal.',
          style: const TextStyle(color: AppColors.dim, fontSize: 11)),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: (p == null || _cargando || _aplicando || !p.puedeAplicar || p.sinCambio)
              ? null
              : _confirmar,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 13)),
          icon: Icon(_aplicando ? Icons.hourglass_top : Icons.swap_horiz, size: 18),
          label: Text(
              _aplicando
                  ? 'Aplicando…'
                  : (p != null && p.sinCambio ? 'Ya está en ese modo' : 'Cambiar modo'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    ]));
  }

  void _elegir({String? destino, String? entorno}) {
    setState(() {
      if (destino != null) _destino = destino;
      if (entorno != null) _entorno = entorno;
    });
    _cargar();
  }

  Widget _aviso(String texto, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          border: Border.all(color: color.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(texto, style: TextStyle(color: color, fontSize: 12.5)),
      );

  List<Widget> _detalle(AfipModoPreview p) {
    return [
      // ★ 막히는 이유는 서버가 갈래로 나눠 준다 — 뭉치지 않고 그대로 보여 준다.
      if (p.bloqueos.isNotEmpty)
        _aviso('No se puede cambiar todavía:\n${p.bloqueos.map((b) => '• $b').join('\n')}',
            AppColors.red),
      ...p.advertencias.map((a) => _aviso(a, AppColors.amber)),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl('Emisores (${p.emisores.length})'),
        if (p.emisores.isEmpty)
          const Text('Esta tienda no tiene emisores.',
              style: TextStyle(color: AppColors.dim, fontSize: 12.5)),
        ...p.emisores.map(_emisorRow),
      ])),
    ];
  }

  Widget _emisorRow(AfipEmisor e) {
    final homo = e.entornoActual == 'homo';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1C2A48)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('PV ${e.puntoVenta.toString().padLeft(5, '0')}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(e.cuit, style: const TextStyle(color: AppColors.dim, fontSize: 12)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (homo ? AppColors.amber : AppColors.dim).withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(homo ? 'Homologación' : 'Producción',
                style: TextStyle(
                    color: homo ? AppColors.amber : AppColors.txt,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 4),
        e.bloqueos.isNotEmpty
            ? Text(e.bloqueos.join(' '),
                style: const TextStyle(color: AppColors.red, fontSize: 11.5))
            : const Text('Listo',
                style: TextStyle(
                    color: AppColors.green, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ...e.advertencias.map((a) => Text(a,
            style: const TextStyle(color: AppColors.amber, fontSize: 11.5))),
      ]),
    );
  }
}
