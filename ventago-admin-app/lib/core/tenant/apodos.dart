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

  static void cargar(Iterable<({int id, String nombre, String? apodo})> tiendas) {
    for (final t in tiendas) {
      final a = t.apodo?.trim() ?? '';
      if (a.isEmpty) continue;
      _porId[t.id] = a;
      _porNombre[t.nombre] = a;
    }
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
