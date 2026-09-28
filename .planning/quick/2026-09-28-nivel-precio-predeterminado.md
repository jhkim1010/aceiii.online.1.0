# Nivel de precio predeterminado (store default price level) — 2026-09-28

## Qué se construyó

Configuración › Ventas ahora tiene una tarjeta «Nivel de precio predeterminado» donde el
admin de un matiz (store) elige con qué nivel de precio arranca cada línea nueva del POS
(`NuevaVenta`). El valor se guarda de inmediato (sin botón «Guardar» — igual que
`InventarioConfigView`) y se aplica a la sesión de POS a través de `StoreConfigContext`.

- **NULL (default)** = «Precio base» (`products.price`, no depende de una fila en `prices`).
- **Un `price_types.id`** = ese nivel arranca seleccionado. El vendedor **puede seguir
  cambiándolo por línea** (gated por `elegir-tipo-de-precio`, sin cambios).
- Si el nivel configurado deja de existir, se desactiva, o pasa a otro matiz — el servidor
  ya no lo deja guardar de nuevo, y el POS cae de vuelta a Precio base automáticamente
  (`resolveInitialPriceType` sólo acepta ids presentes + activos en la lista actual).

## Dónde vive cada pieza

| Pieza | Archivo |
|---|---|
| Columna DB | `store_configs.default_price_type_id` (migración abajo) |
| Modelo Sequelize | `api-ventago/src/app/store/config/storeConfig.model.ts` |
| Validación + guardado | `api-ventago/src/app/store/config/storeConfig.service.ts` → `updateDefaultPriceType()` |
| Endpoint | `PUT /store-config/:storeId/default-price-type` (`storeConfig.controller.ts`) |
| Lógica pura de selección (POS) | `ventago-app/src/utils/price-types.ts` → `resolveInitialPriceType(list, storeDefaultId)` |
| Contexto | `ventago-app/src/context/StoreConfigContext.tsx` → `defaultPriceTypeId` |
| UI de configuración | `ventago-app/src/views/config/ventas/nivelPrecioPredeterminado/NivelPrecioPredeterminadoCard.tsx` |
| Wiring en POS | `ventago-app/src/views/homes/components/ProductList/components/ProductsInputs.tsx` (`pickDefaultPriceType`, efecto de arranque) |

## Decisión de diseño clave (por qué no se tocó `basePriceType`)

`ProductsInputs.tsx` ya tenía un concepto `basePriceType` (el tipo «PRECIO 1»/base real)
que `resolveAmountFor()` usa para un caso especial: si un producto no tiene fila en
`prices` para ese tipo, el precio se lee de `products.price` directamente. **Ese caso
especial no se puede generalizar a «el tipo por defecto de la tienda»** — si el default
fuera, por ejemplo, «PRECIO 3» (un nivel derivado), tratarlo como si equivaliera a
`products.price` inventaría un precio que no existe.

Por eso se agregó un concepto **separado**, `initialPriceType` (vía `resolveInitialPriceType`),
que sólo decide **qué aparece seleccionado al principio**. La resolución de montos
(`resolveAmountFor`) sigue intacta: si el producto no tiene fila para el nivel por defecto,
el campo de precio queda vacío (correcto — ese nivel no está definido para ese producto) en
vez de mostrar un monto inventado.

Cuando no hay default configurado, `initialPriceType` resuelve exactamente al mismo valor
que `basePriceType` (mismo `isBaseLikePriceType`), así que el comportamiento previo es
bit-a-bit idéntico — no hay regresión para las tiendas que no toquen esta configuración
nueva.

## Listas de campos revisadas (requisito del pedido)

- **`store-restore-columns.txt`** — baseline de columnas para backup/restore de matiz.
  Se agregó `store_configs.default_price_type_id : integer` (nullable, sin default) en
  orden alfabético. Verificado contra DB local (`\d store_configs`).
- **`store-restore-fk-catalog.txt`** — baseline de FKs para el motor de restore/clonado.
  Se agregó `store_configs.default_price_type_id -> public.price_types.id [NULLABLE]`.
  No requiere una regla explícita en `store-restore-manifest.ts` — `price_types` es una
  tabla dentro del alcance de clonado (`SIMPLE_STORE_TABLES`/`CUSTOM_HANDLED_TABLES`), así
  que `resolveFk()` la resuelve como `REMAP` automáticamente (el id se remapea al nuevo
  `price_types.id` del matiz clonado).
- **`store-backup-keys.ts`** — mapea **tablas completas** (`store_configs` → `storeConfigs`)
  para el backup JSON, no columnas individuales. Ya incluye `store_configs` desde antes;
  no requiere cambios — el backup ORM (`toJSON()`) ya expone la columna nueva
  automáticamente en cuanto se agrega al modelo.
- **`mobile-auth.service.ts`** — se revisó y **no se tocó**. Sólo proyecta un campo puntual
  de `StoreConfig` (`allowSaleWithoutStock`) para la app Flutter (gate de venta sin stock);
  no es una lista exhaustiva de todos los campos de `store_configs` ni hay spec que exija
  completitud ahí. La app Flutter no comparte el flujo de `ProductsInputs.tsx` de
  `ventago-app`, así que agregar `defaultPriceTypeId` ahí queda fuera del alcance de este
  pedido (no se mencionó una pantalla de venta en la app móvil que lo necesite).
- **`StoreConfigContext.tsx`** (interfaz + `defaultState` + mapeo) — hecho, ver tabla arriba.

## Commits

### api-ventago
- `c69844ff` — `feat(store-config): add default_price_type_id migration (expand only)`
  (migración SQL, sin código de aplicación)
- `be264afa` — `feat(store-config): add default price type API + tenant-scoped validation`
  (modelo, servicio, controlador, tests, baselines de restore)

### ventago-app
- `ccc8dbb2` — `feat(price-types): add resolveInitialPriceType for store default level`
  (función pura + test, con evidencia de mutación)
- `c6b85ea1` — `feat(config): add Nivel de precio predeterminado card in Configuración > Ventas`
  (StoreConfigContext + tarjeta de configuración)
- `b432285c` — `feat(pos): wire store default price type into ProductsInputs initial selection`
  (wiring en POS)

### Repo raíz
- Este archivo (`.planning/quick/2026-09-28-nivel-precio-predeterminado.md`)

**No se movió el puntero de submódulo en el repo raíz** (instrucción explícita del
orquestador) — los commits arriba viven en las ramas `main` de `api-ventago` y
`ventago-app` respectivamente, pero el repo raíz no los referencia todavía.

## Tests

### Backend (api-ventago)
- `src/app/store/config/storeConfig.default-price-type.spec.ts` (nuevo) — 4 casos:
  - `priceTypeId=null` → no consulta `price_types`, guarda `null` (vuelve a Precio base).
  - `priceTypeId` del mismo store + activo → guarda.
  - `priceTypeId` de **otro store** (IDOR) → `BadRequestException`, no guarda
    (tenant isolation).
  - `priceTypeId` **inactivo** → `BadRequestException`, no guarda.
- `src/app/store/config/storeConfig.controller.spec.ts` (extendido) — delegación al
  service, validación de `priceTypeId` no numérico / `<= 0`, y ownership (admin de otro
  matiz → `ForbiddenException` antes de tocar el service).
- Ejecución: `env -u NODE_OPTIONS npx jest src/app/store src/common/migrations/migration-conventions.spec.ts --maxWorkers=1`
  → **395 tests, 394 passed, 1 failed** (la 1 fallada es preexistente y no relacionada —
  ver sección «Fallo preexistente» abajo).

### Frontend (ventago-app)
- `src/__tests__/nivel-precio-predeterminado.spec.ts` (nuevo) — 8 casos sobre
  `resolveInitialPriceType`, incluyendo los 4 pedidos explícitamente:
  - default seteado y activo → ese.
  - default seteado pero ausente/inactivo → Precio base.
  - sin default → Precio base (fila PRECIO 1).
  - lista vacía → `null`.
  - + casos extra: sin base en la lista y sin default → `null`; comparación de id
    string vs number.
- Ejecución: `env -u NODE_OPTIONS npx jest src/__tests__/nivel-precio-predeterminado.spec.ts --maxWorkers=1`
  → **8/8 passed**.
- Regresión: se corrió también `precio-base-label.spec.ts` y
  `pos-precio-lista-igual-al-cobro.spec.ts` (specs existentes que tocan la misma zona de
  precios en POS) → **24/24 passed**, sin regresiones.

### Evidencia de mutación
- **Backend**: no aplica una mutación de código de producción per se — los 4 tests del
  service ejercitan las 4 ramas de `updateDefaultPriceType` directamente (null, válido,
  otro-store, inactivo), cada una con un `mockResolvedValue` distinto que hace fallar las
  otras 3 aserciones si se intercambian.
- **Frontend**: se mutó `resolveInitialPriceType` (`Number(pt.id) === Number(storeDefaultId)`
  → `false`, forzando a que nunca encuentre el default) y se confirmó que **2 de 8 tests
  fallan** (el de "default activo → ese" y el de comparación string/number), luego se
  restauró el archivo original (`git diff --stat` confirma 0 cambios respecto al commit).

## SQL exacto de la migración (aplicada en LOCAL, `psql -p 5432 -d ventago`, NO en prod 5434)

Archivo: `api-ventago/migrations/2026-09-28-d-store-config-default-price-type.sql`

```sql
SET lock_timeout = '5s';

ALTER TABLE store_configs
  ADD COLUMN IF NOT EXISTS default_price_type_id INTEGER NULL;

-- PG no soporta `ADD CONSTRAINT IF NOT EXISTS` — chequeo de existencia para poder
-- re-ejecutar el archivo sin error (probado dos veces, ver abajo).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_store_configs_default_price_type'
  ) THEN
    ALTER TABLE store_configs
      ADD CONSTRAINT fk_store_configs_default_price_type
      FOREIGN KEY (default_price_type_id) REFERENCES price_types(id)
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;

ALTER TABLE store_configs
  VALIDATE CONSTRAINT fk_store_configs_default_price_type;

COMMENT ON COLUMN store_configs.default_price_type_id IS
  'Nivel de precio con el que arranca cada línea nueva en POS. NULL = Precio base
   (products.price). Se valida server-side que pertenezca al mismo store y esté
   activo (status=1).';

-- Verificación — columna + constraint existen y el FK quedó VALIDATED.
DO $$ ... RAISE EXCEPTION si falta algo, RAISE NOTICE si OK ... END $$;
```

- Convención W4 (expand-only, sin `contract`): columna nullable, sin backfill (todas
  las filas existentes quedan en `NULL` = comportamiento idéntico al actual). FK agregada
  `NOT VALID` y validada en sentencia separada (lock débil). `SET lock_timeout='5s'` al
  inicio del archivo.
- **Aplicada dos veces en local para probar idempotencia** — la segunda corrida sólo
  emite `NOTICE: column ... already exists, skipping` y termina sin error (exit code 0).
- **Verificado con `\d store_configs`**: columna `default_price_type_id | integer |
  | |` (nullable, sin default) + `"fk_store_configs_default_price_type" FOREIGN KEY
  (default_price_type_id) REFERENCES price_types(id) ON DELETE SET NULL`.

## Impacto esperado en producción (cuando se aplique — no se aplicó en esta tarea)

- **0 filas de `store_configs` cambian de valor** — la columna nueva nace en `NULL` para
  las 100% de las filas existentes, que es exactamente el valor que hoy el código
  interpreta como «Precio base» (comportamiento actual, sin cambios).
- **0 tiempo de bloqueo relevante** — `ADD COLUMN ... NULL` no reescribe la tabla en
  PG18; el `FOREIGN KEY ... NOT VALID` tampoco bloquea escrituras concurrentes; el
  `VALIDATE CONSTRAINT` toma un lock débil (`SHARE UPDATE EXCLUSIVE`) y sólo lee, no
  escribe.
- **Sin paso de `contract`** — el código viejo (antes del deploy del backend) simplemente
  no lee ni escribe esta columna; el código nuevo la lee con `?? null`, así que el orden
  de deploy backend/frontend no importa para esta pieza en particular (a diferencia del
  ejemplo de caja del CLAUDE.md, acá no hay in compatibilidad de contrato).
- **Antes de aplicar en prod (5434)**: correr el mismo archivo con
  `sudo -u postgres psql -p 5434 -d ventago -v ON_ERROR_STOP=1 --single-transaction -f
  api-ventago/migrations/2026-09-28-d-store-config-default-price-type.sql`, y además
  transferir el owner de la nueva columna/constraint no es necesario (no crea tabla ni
  secuencia nueva — sólo agrega columna+FK a una tabla existente cuyo owner ya es
  `coolsistema`).

## Qué falta para llevar esto a producción (fuera del alcance de esta tarea, por instrucción explícita)

1. Aplicar la migración en LOCAL de la persona que continúe (ya aplicada acá) — **falta
   aplicarla en prod (5434)** con el comando de arriba, con aprobación previa (regla del
   proyecto: DML/DDL en prod requiere aprobación explícita).
2. `git push` de `api-ventago` y `ventago-app` (no se hizo — instrucción explícita de no
   pushear en esta tarea).
3. Actualizar los punteros de submódulo en el repo raíz (no se hizo — instrucción
   explícita).
4. Build de Jenkins (`api-new-coolsistema`, `front-coolsistema`) tras el push.

## Fallo preexistente (no relacionado, no se tocó)

`api-ventago/src/app/store/store-backup-coverage.spec.ts` falla con o sin los cambios de
esta tarea — tablas de migraciones recientes de **otro trabajo** (`store_exchange_rates`,
`terminal_printers`, `notas*`) no están declaradas en `store-backup-coverage.ts`.
Verificado con `git stash` que el fallo es idéntico antes y después de este cambio. Se
usó `SKIP_VERIFY=1` para el commit `be264afa` con el motivo documentado en el mensaje de
commit (regla del proyecto: `SKIP_VERIFY` no se usa en silencio).
