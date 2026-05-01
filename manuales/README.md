# Manuales — Knowledge base del AI agent

Esta carpeta contiene los manuales de uso del sistema Ventago. El AI agent
(chat) usa estos archivos como base de conocimiento (RAG) para responder
las preguntas de los usuarios.

## Cómo agregar o editar un manual

1. Crear un archivo `.md` en esta carpeta. Ejemplo: `inventario.md`,
   `dashboards.md`, `configuracion.md`.
2. Escribir el contenido en formato markdown.
3. Hacer commit y push.
4. En el próximo despliegue (o en el próximo cron de las 03:00), el
   `ManualSyncService` del backend leerá el archivo y lo registrará en la
   tabla `knowledge_documents`.
5. Si querés reflejar el cambio inmediatamente sin esperar al cron, llamar
   al endpoint manual:

   ```
   POST /api/chat/sync-manuales
   Authorization: Bearer <jwt>
   ```

## Reglas de formato

### Estructura

- **`# Título del manual`** (un solo `#` al principio del archivo) — se
  ignora en la indexación; sirve solo para identificar el archivo.
- **`## Sección`** (dos `##`) — cada sección se convierte en un documento
  separado en `knowledge_documents`. El título de la sección es el
  `title` del documento, y el contenido es el `content`.
- **`### Subsección`** (tres `###`) — queda dentro de la sección
  contenedora, no genera un documento nuevo.

### Source

El backend genera automáticamente el campo `source` con el formato:

```
manuales/<archivo>.md#<slug-de-la-seccion>
```

Ejemplo: `manuales/credito_senia_favor.md#como-vender-a-credito`.

Si modificás el título de una sección, el slug cambia y se considera un
documento nuevo (el viejo se borra automáticamente al detectarse como
huérfano en el próximo sync).

### Buenas prácticas

- **Títulos de sección descriptivos** — usar palabras clave que el usuario
  podría escribir al preguntar. Ejemplo: "Cómo registrar una Seña" mejor
  que "Procedimiento 4.2".
- **Una sección por tema** — secciones cortas y enfocadas tienen mejor
  matching que secciones largas con muchos temas mezclados.
- **Incluir términos técnicos y coloquiales** — ej: "Seña (reserva,
  anticipo, pago adelantado)" para que la búsqueda los encuentre por
  cualquier palabra.
- **Usar listas y pasos numerados** — facilita que el AI responda con
  pasos claros.
- **No incluir imágenes** — el AI no las puede leer, y aumentan el peso
  innecesariamente.

## Manuales actuales

| Archivo | Tema | Idioma |
|---------|------|--------|
| `credito_senia_favor.md` | Cuenta corriente: visión general (crédito, seña, favor) | Español |
| `venta_a_credito.md` | Cómo vender a crédito (paso a paso) | Español |
| `cobro_credito.md` | Cómo cobrar un crédito cuando el cliente viene a pagar | Español |

## Próximos manuales planificados

- `inventario.md` — gestión de stocks, ProductBranch, transferencias
- `dashboards.md` — interpretación de los dashboards
- `configuracion.md` — administración del sistema, sucursales, usuarios
- `cierre_caja.md` — cierre diario de caja, control de caja
- `produccion.md` — gestión de producción y BOM
- `subcon.md` — gestión de talleres externos

## Cómo verificar que el AI lo aprendió

Después del sync, podés probar:

1. Ir al chat del AI agent.
2. Preguntar algo de la sección. Ej: "¿Cómo registro una seña?"
3. La respuesta debería citar el manual o dar pasos directos del contenido.

Si el AI no encuentra la información, revisar:

- Que el archivo esté en la carpeta correcta (`manuales/`).
- Que tenga la extensión `.md`.
- Que el formato `## Sección` esté bien (no `# `).
- Que el sync corrió: ver logs del backend `[ManualSync]` o consultar
  `GET /api/chat/knowledge` para ver la lista actual.

## Idiomas

Los manuales están en español por defecto (los usuarios finales son
hispanohablantes). Si se necesita otro idioma para una operación
específica, crear un archivo separado: `inventario_en.md`, `inventario_pt.md`.
El AI agent maneja automáticamente la respuesta en el idioma del usuario.
