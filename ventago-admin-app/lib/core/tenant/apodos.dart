// [2026-10-20 usuario] «los nombres de las tiendas en la app superadmin, con el apodo».
//
// El servidor sigue mandando el nombre (`storeName`/`tienda`: la web usa los mismos endpoints).
// El apodo (`stores.alias_name`) sólo llega en GET /admin-console/tenants; acá se guarda una vez
// y cada modelo traduce el nombre al leer el JSON. Algunos endpoints (Actividad, Pedidos) no
// mandan storeId → se busca también por nombre.
class Apodos {
  Apodos._();

  static final Map<int, String> _porId = {};
  static final Map<String, String> _porNombre = {};

  /// Reemplaza la tabla entera con la lista completa de tiendas.
  /// [CODEX] un nombre que tienen DOS tiendas no se traduce por nombre (sería adivinar).
  static void cargar(Iterable<({int id, String nombre, String? apodo})> tiendas) {
    final porId = <int, String>{};
    final porNombre = <String, String>{};
    final repetidos = <String>{};
    for (final t in tiendas) {
      final a = t.apodo?.trim() ?? '';
      if (porNombre.containsKey(t.nombre) || repetidos.contains(t.nombre)) {
        repetidos.add(t.nombre);
        porNombre.remove(t.nombre);
      }
      if (a.isEmpty) continue;
      porId[t.id] = a;
      if (!repetidos.contains(t.nombre)) porNombre[t.nombre] = a;
    }
    _porId
      ..clear()
      ..addAll(porId);
    _porNombre
      ..clear()
      ..addAll(porNombre);
  }

  /// Apodo de la tienda si se conoce; si no, el nombre tal cual.
  static String de(int? storeId, String nombre) {
    if (storeId != null && _porId.containsKey(storeId)) return _porId[storeId]!;

    return _porNombre[nombre] ?? nombre;
  }

  /// Igual que [de] para campos opcionales.
  static String? deOpt(int? storeId, String? nombre) =>
      nombre == null ? null : de(storeId, nombre);
}
