// [2026-09-05] 전자 영수증(fac. electrónica)을 쓰는 매장 목록 + 인증서 갱신 시한.
//
// ★ 급한 것이 위로 온다 — 정렬은 **서버가** 한다. 앱이 다시 정렬하면 배지와 목록이
//   갈라진다(서버의 `necesitaAtencion` 하나가 유일한 판정이다).
//
// ★★ 홈올로가시온은 눈에 띄게 구분한다. 그 전표는 **세무상 무효**라서, 같아 보이면
//   「발급되고 있으니 괜찮다」고 읽게 된다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'facturacion_repository.dart';

class FacturacionScreen extends ConsumerWidget {
  const FacturacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(facElectronicaProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(facElectronicaProvider),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            const SizedBox(height: 80),
            Center(child: Text('No se pudo cargar: $e')),
          ],
        ),
        data: (r) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Resumen(r: r),
            if (r.dirError != null) _DirError(msg: r.dirError!),
            const SizedBox(height: 8),
            ...r.items.map((i) => _Fila(item: i, diasAviso: r.diasAviso)),
            const SizedBox(height: 12),
            Text(
              'Certificados en ${r.certsDir}\nÚltima lectura: ${r.scannedAt}',
              style: const TextStyle(color: AppColors.dim, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.r});
  final FacElectronicaResult r;

  @override
  Widget build(BuildContext context) {
    final urgente = r.porRenovar > 0;

    return Card(
      color: urgente ? const Color(0xFF3A1E1E) : AppColors.navy2,
      child: ListTile(
        leading: Icon(
          urgente ? Icons.warning_amber_rounded : Icons.verified_outlined,
          color: urgente ? Colors.redAccent : AppColors.gold,
          size: 32,
        ),
        title: Text(
          urgente
              ? '${r.porRenovar} necesita(n) renovación'
              : 'Todos los certificados al día',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${r.total} punto(s) de venta con facturación electrónica'
          ' · aviso a ${r.diasAviso} días',
          style: const TextStyle(color: AppColors.dim, fontSize: 12),
        ),
      ),
    );
  }
}

class _DirError extends StatelessWidget {
  const _DirError({required this.msg});
  final String msg;

  @override
  Widget build(BuildContext context) {
    // 디렉터리를 통째로 못 읽었다 = 개별 인증서가 아니라 마운트 문제다.
    // 이때 아래 목록의 「인증서 없음」은 사실이 아닐 수 있으므로 그렇게 말한다.
    return Card(
      color: const Color(0xFF3A1E1E),
      child: ListTile(
        leading: const Icon(Icons.folder_off_outlined, color: Colors.redAccent),
        title: const Text('No se pudo leer el directorio de certificados'),
        subtitle: Text(
          '$msg\nLo de abajo puede no reflejar la realidad.',
          style: const TextStyle(color: AppColors.dim, fontSize: 12),
        ),
      ),
    );
  }
}

({Color color, String texto, IconData icon}) _estilo(
  EstadoCert e,
  int? dias,
) {
  switch (e) {
    case EstadoCert.vencido:
      return (
        color: Colors.redAccent,
        texto: 'VENCIDO${dias != null ? ' hace ${-dias}d' : ''}',
        icon: Icons.dangerous_outlined,
      );
    case EstadoCert.porRenovar:
      return (
        color: Colors.orangeAccent,
        texto: 'Renovar en ${dias ?? '?'}d',
        icon: Icons.warning_amber_rounded,
      );
    case EstadoCert.ilegible:
      return (
        color: Colors.orangeAccent,
        texto: 'Ilegible',
        icon: Icons.help_outline,
      );
    case EstadoCert.sinCertificado:
      return (
        color: AppColors.dim,
        texto: 'Sin certificado',
        icon: Icons.upload_file_outlined,
      );
    case EstadoCert.ok:
      return (
        color: Colors.greenAccent,
        texto: '${dias ?? '?'}d',
        icon: Icons.verified_outlined,
      );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.item, required this.diasAviso});
  final FacElectronicaItem item;
  final int diasAviso;

  @override
  Widget build(BuildContext context) {
    final st = _estilo(item.estado, item.daysLeft);

    return Card(
      color: AppColors.navy2,
      child: ListTile(
        leading: Icon(st.icon, color: st.color),
        title: Row(
          children: [
            Flexible(
              child: Text(
                item.storeName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            // ★ 홈올로가시온은 반드시 눈에 띄어야 한다 — 전표가 세무상 무효다.
            if (!item.produccion)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'HOMO',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'PV ${item.puntoVenta}'
          '${item.invoiceType != null ? ' · Tipo ${item.invoiceType}' : ''}'
          '${item.cuit != null ? ' · CUIT ${item.cuit}' : ''}\n'
          '${item.provider ?? '-'}'
          '${item.autoIssue ? ' · auto' : ' · manual'}'
          ' · ${item.vouchers} emitida(s)'
          '${item.ultimaEmision != null ? ' (última ${item.ultimaEmision})' : ''}'
          '${item.certError != null ? '\n${item.certError}' : ''}',
          style: const TextStyle(color: AppColors.dim, fontSize: 12),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              st.texto,
              style: TextStyle(
                color: st.color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (item.validTo != null)
              Text(
                item.validTo!,
                style: const TextStyle(color: AppColors.dim, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
