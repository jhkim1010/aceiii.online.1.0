# 📋 Guía completa de CRM — Ventago

**Sistema:** Ventago POS/ERP
**Versión:** 2026-05-13 (Phase 29 Wave B incluida)
**Audiencia:** Administradores y empleados de los locales (CART · coolsistema · genius · ACE)

---

## 📚 Índice

1. [Introducción al CRM de Ventago](#1-introducción-al-crm-de-ventago)
2. [Gestión de clientes (ClienteVista)](#2-gestión-de-clientes-clientevista)
3. [Clientes globales y carga masiva](#3-clientes-globales-y-carga-masiva)
4. [Cuentas corrientes y crédito](#4-cuentas-corrientes-y-crédito)
5. [Reportes de clientes](#5-reportes-de-clientes)
6. [WhatsApp Click-to-Chat (Phase 29 Wave B)](#6-whatsapp-click-to-chat-phase-29-wave-b)
7. [Roadmap — próximas funcionalidades CRM](#7-roadmap--próximas-funcionalidades-crm)
8. [Buenas prácticas de gestión de clientes](#8-buenas-prácticas-de-gestión-de-clientes)
9. [Solución de problemas frecuentes](#9-solución-de-problemas-frecuentes)

---

## 1. Introducción al CRM de Ventago

### ¿Qué es el CRM?

CRM (Customer Relationship Management) significa **gestión de relaciones con clientes**. En Ventago, el CRM es el conjunto de herramientas que te permite:

- 📝 **Registrar** información de cada cliente (nombre, CUIT/DNI, teléfono, dirección)
- 🔍 **Buscar y consultar** clientes rápidamente
- 💳 **Gestionar créditos** (cuenta corriente, deudas, señas)
- 📊 **Ver reportes** de clientes con saldos pendientes
- 📱 **Comunicarse** con clientes vía WhatsApp (Phase 29 Wave B)

### Arquitectura del CRM en Ventago

Ventago tiene una estructura especial para clientes que permite **compartir información entre locales del mismo grupo** sin perder la independencia operativa de cada local:

```
GlobalClient (información común — CUIT, nombre, teléfono)
    ↓
StoreClient (vinculación por local — crédito, estado activo/inactivo)
    ↓
Clients (datos legacy del local — se sincronizan automáticamente)
```

> 💡 **¿Por qué importa esto?** Si el cliente *María Rodríguez (CUIT 27-32145678-4)* compra en CART y después va a ACE, **sus datos ya aparecen automáticamente** sin necesidad de cargarlos de nuevo. El crédito sigue siendo independiente por local.

### Locales operativos actuales

| ID | Nombre | Admins |
|---|---|---|
| 3 | CART | CARLOS, Alejandro, Matias |
| 6 | coolsistema | jungho, israel |
| 8 | genius | angel |
| 9 | ACE | Marcos (3 cuentas), Israel |

---

## 2. Gestión de clientes (ClienteVista)

### Acceso

```
Menú lateral → ClienteVista
```

Ruta: `https://app.coolsistema.com/cliente-vista`

### Pantalla principal

La pantalla muestra:

- **3 tarjetas de estadísticas:** Total / Activos / Inactivos
- **Barra de búsqueda** (busca por nombre, CUIT, teléfono, email)
- **Filtros rápidos:** Todos · Activos · Inactivos
- **Tabla de clientes** con acciones por fila
- **Botones de acción:** Carga Masiva · Historial · Nuevo Cliente

### Crear un cliente nuevo

1. Hacé click en **[Nuevo Cliente]** (arriba a la derecha)
2. Completá los campos obligatorios:
   - **Nombre completo*** (obligatorio)
   - **Documento (CUIT/DNI)*** (obligatorio)
3. Campos opcionales recomendados:
   - **Teléfono** — necesario para enviar WhatsApp
   - **Nombre de fantasía** — para empresas
   - **Email**
   - **Resp. IVA** (Responsable / Monotributista / Consumidor Final)
   - **Dirección + Ubicación + Provincia**
   - **Transporte** — si el cliente tiene logística asociada
   - **Notas** — observaciones internas
4. Hacé click en **[Guardar]**

> 💡 **Tip:** Si el cliente todavía no te dio el CUIT/DNI pero querés registrar la venta, podés crear un **cliente temporal** desde la pantalla de Nueva Venta. El sistema le asigna un número de serie automático.

### Editar un cliente

1. En la tabla, buscá al cliente
2. Hacé click en el ícono ✏️ (lápiz)
3. Modificá los campos necesarios
4. Hacé click en **[Guardar]**

### Desactivar un cliente

> ⚠️ **No se borra físicamente** — esto se llama "soft delete". El registro y todas sus ventas se conservan, pero el cliente no aparece más en la lista activa.

1. Hacé click en el ícono 🗑️ (tacho)
2. Confirmá la desactivación
3. El cliente queda con estado **Inactivo**

**¿Por qué soft delete?** Porque si borráramos al cliente, también se borrarían todas sus ventas asociadas (integridad referencial). Eso violaría la normativa contable y AFIP.

### Reactivar un cliente desactivado

1. Filtro **Inactivos** arriba a la derecha
2. Encontrá al cliente
3. Por ahora la reactivación requiere intervención del admin a nivel DB. Próximamente se agregará botón directo.

### Promover cliente a Global

Si un cliente está solo en tu local (legacy) y querés que aparezca en otros locales del grupo:

1. Editá al cliente
2. Asegurate de que tenga **CUIT/DNI válido** (requisito)
3. El sistema lo "promueve" automáticamente al GlobalClient

### Validación de CUIT

Ventago valida automáticamente:

- **CUIT:** 11 dígitos + verificador
- **DNI:** 7 u 8 dígitos
- Formato libre — el sistema normaliza espacios y guiones

---

## 3. Clientes globales y carga masiva

### ¿Qué son los Clientes Globales?

Los **GlobalClient** son la "base de datos común" de todos los locales del grupo. Sirven para:

- Evitar duplicación de datos
- Compartir información de contacto entre locales
- Centralizar la gestión de clientes corporativos

### Acceder a la lista global

```
Menú lateral → Clientes Globales
```

Ruta: `https://app.coolsistema.com/clientes-globales`

### Carga masiva (CSV / Excel)

> 👑 Requiere permiso `manage-clientes-import`.

#### Paso 1: Descargar plantilla

Desde **ClienteVista** → botón **[Carga Masiva]** (arriba a la derecha).

#### Paso 2: Preparar el archivo

Columnas obligatorias y opcionales:

| Columna | Obligatorio | Ejemplo |
|---|---|---|
| `document` | ✅ | `27321456784` |
| `fullname` | ✅ | `María Rodríguez` |
| `nameFantasy` | ⬜ | `Boutique María` |
| `email` | ⬜ | `maria@ejemplo.com` |
| `phone` | ⬜ | `+5491145678901` |
| `address` | ⬜ | `Av. Corrientes 1234` |
| `location` | ⬜ | `CABA` |
| `province` | ⬜ | `Buenos Aires` |
| `resIva` | ⬜ | `Responsable Inscripto` |
| `transport` | ⬜ | `Andreani` |
| `note` | ⬜ | `Cliente VIP — descuento 10%` |

> ⚠️ **Importante:** Sin CUIT/DNI válido, el cliente **NO** se sube a GlobalClient (queda solo en el legacy del local).

#### Paso 3: Subir el archivo

1. Hacé click en **[Carga Masiva]**
2. Arrastrá el archivo CSV o Excel al área de carga
3. El sistema valida cada fila
4. Mostrará: **Creados** / **Actualizados** / **Saltados** / **Errores**

#### Paso 4: Revisar el resultado

- Filas creadas: nuevos clientes
- Filas actualizadas: clientes existentes con datos nuevos
- Filas saltadas: duplicados sin cambios
- Errores: filas con problemas (CUIT inválido, formato incorrecto)

### Historial de cargas masivas

> 👑 Requiere permiso `view-clientes-import-history`.

```
ClienteVista → botón [Historial]
```

Permite ver:
- Fechas de cargas previas
- Quién las hizo
- Resumen de filas procesadas

---

## 4. Cuentas corrientes y crédito

### ¿Qué es una cuenta corriente?

Cuando un cliente compra "a crédito" (paga después), Ventago lleva un **registro de cuenta corriente** con:

- 💰 Saldo pendiente (deuda)
- 📅 Fechas de las compras a crédito
- 📥 Pagos parciales recibidos
- 🎯 Vencimientos

### Acceder a cuentas corrientes

```
Menú lateral → Cuentas Corrientes
```

### Registrar una venta a crédito

1. En **Nueva Venta**, después de agregar productos
2. En **Forma de pago**, seleccioná **Crédito**
3. El sistema verifica el límite de crédito del cliente
4. Confirmá la venta
5. El monto queda como saldo pendiente

### Registrar un pago

1. Buscá al cliente en **Cuentas Corrientes**
2. Hacé click en **[Registrar pago]**
3. Ingresá el monto recibido
4. Seleccioná el método de pago (efectivo, transferencia, etc.)
5. Confirmá — el saldo se actualiza automáticamente

### Seña (anticipo)

Si el cliente paga por adelantado:

1. **Nueva Venta** → seleccionar **Seña** como forma de pago
2. El monto queda como "saldo a favor" del cliente
3. En la próxima compra, ese saldo se descuenta automáticamente

### Configurar límite de crédito

1. Editar cliente → sección **Crédito**
2. Establecer **límite máximo** ($)
3. Establecer **plazo en días**
4. Guardar

> 💡 **Tip:** Si un cliente intenta comprar a crédito superando su límite, Ventago bloquea la venta y muestra alerta.

---

## 5. Reportes de clientes

### Clientes con crédito (saldos pendientes)

```
Menú lateral → Reportes → Clientes con crédito
```

Ruta: `https://app.coolsistema.com/reportes/clientes-credito`

Muestra:
- Lista de clientes con saldo pendiente
- Monto adeudado por cliente
- Días vencidos
- Filtros por sucursal y rango de fechas
- Exportar a Excel

### Análisis rápido

**Métricas clave a observar:**

- **Saldo total pendiente** del local (suma de todas las deudas)
- **Antigüedad de la deuda** — clientes con +30 días vencidos
- **Tasa de cobrabilidad** — pagos recibidos / total adeudado

> 💡 **Buena práctica:** Revisar este reporte **una vez por semana** y enviar recordatorios de WhatsApp a los clientes con deudas vencidas.

---

## 6. WhatsApp Click-to-Chat (Phase 29 Wave B)

> 🆕 **Función nueva agregada el 2026-05-13.**

### ¿Qué es?

Permite enviar mensajes de WhatsApp a los clientes con un solo click, **usando el número del admin del local como remitente**. Costo $0, sin APIs externas, sin riesgo de bloqueo.

### Resumen rápido

1. **Configurá una vez:** `Configuración → WhatsApp` → registrá tu número + designá representante
2. **En el día a día:** `ClienteVista` → click en botón verde de WhatsApp en la fila del cliente → elegí plantilla → completá variables → [Abrir WhatsApp]
3. **El mensaje se envía desde WhatsApp Web** con un solo click adicional

### Plantillas disponibles

| Plantilla | Categoría | Uso típico |
|---|---|---|
| 🎂 Saludo de cumpleaños | Marketing | Día del cumpleaños del cliente |
| ⚠️ Recordatorio de crédito | Utility | Deuda próxima a vencer |
| 💔 Te extrañamos (60d+) | Marketing | Cliente inactivo |
| 🆕 Nuevo producto | Marketing | Anuncio de stock nuevo |
| 🧾 Reenvío de comprobante | Utility | Cliente pide ticket de venta anterior |

### Guía completa

Para detalles completos, ver el documento:

📄 **[Guía de uso — WhatsApp Click-to-Chat](./whatsapp-click-to-chat-guia.md)**

Incluye:
- Configuración inicial paso a paso
- Detalle de cada plantilla con ejemplos
- 9 preguntas frecuentes
- 7 escenarios de solución de problemas
- Consideraciones de privacidad

---

## 7. Roadmap — próximas funcionalidades CRM

### Wave A — Cliente 360 (próximo)

Vista única consolidada de cada cliente:

- 👤 **Header del cliente:** Nombre, CUIT, contacto, segmento (VIP/Leal/Regular/En riesgo/Dormido)
- 📊 **KPIs:** LTV, frecuencia de visitas, ticket promedio, saldo pendiente
- 📅 **Timeline de compras:** Últimas 20 ventas con fechas
- 🔥 **Top 5 productos** que más compra el cliente
- 🏷️ **Tags personalizados:** VIP, Mayorista, Empresa, etc.
- 🎂 **Cumpleaños y aniversarios** con alertas D-1 / D-3 / D-7

**Acceso futuro:** Click en cualquier fila de ClienteVista → vista 360

### Wave A — Segmentación RFM

Clasificación automática diaria de todos los clientes:

| Segmento | Criterio | Acción recomendada |
|---|---|---|
| ⭐ VIP | R≥4, F≥4, M≥4 | Beneficios exclusivos, comunicación frecuente |
| 💚 Leales | R≥3, F≥3 | Mantener engagement |
| 🔵 Regulares | 2-3 meses sin visita | Marketing general |
| ⚠️ En riesgo | R≤2 (era VIP/Leal) | **Acción inmediata** — winback |
| 💤 Dormidos | 60+ días sin visita | Campaña de reactivación |

### Wave C — Automatización

- 📅 **Envío automático de cumpleaños** — cron diario detecta clientes que cumplen años
- 📅 **Recordatorios de crédito automáticos** — D-3 antes del vencimiento
- 📅 **Re-engagement de inactivos** — cron 60 días
- 📅 **Plantillas personalizadas por local**
- 📅 **Envío masivo por segmento**
- 📅 **Métricas de campañas** (tasa de apertura, conversión)

### Bajo evaluación (sujeto a demanda)

- 🤔 **Sistema de puntos / loyalty**
- 🤔 **Niveles de cliente (Bronze/Silver/Gold)** con descuentos automáticos
- 🤔 **NPS** (encuesta de satisfacción 1-10)
- 🤔 **Integración con Meta Cloud API** para envío masivo profesional

---

## 8. Buenas prácticas de gestión de clientes

### ✅ Hacer

1. **Pedir siempre CUIT/DNI** — habilita acceso a GlobalClient y al sistema completo de crédito
2. **Verificar teléfono** — sin teléfono no podés enviar WhatsApp
3. **Mantener `is_active` actualizado** — clientes que ya no compran → desactivar
4. **Revisar reporte de crédito semanal** — detectar deudas vencidas a tiempo
5. **Usar plantillas estándar de WhatsApp** — consistencia de marca + tono profesional
6. **Documentar notas internas** — observaciones útiles para próximas atenciones
7. **Backup de datos importantes** — el equipo técnico hace backup automático, pero exportá tus reportes mensuales

### ❌ Evitar

1. **No crear clientes duplicados** — buscá primero por CUIT antes de crear uno nuevo
2. **No usar el campo `note` para datos sensibles** — números de tarjeta, claves, etc.
3. **No enviar WhatsApp masivos sin segmentación** — los clientes se molestan y se dan de baja
4. **No compartir tu número de WhatsApp con vendedores que no lo necesitan** — privacidad
5. **No borrar clientes con compras históricas** — usá desactivar (`is_active=false`) en su lugar
6. **No subir CSVs con teléfonos en formato inconsistente** — Ventago intenta normalizar, pero números muy malformados pueden fallar

### 🎯 KPIs sugeridos para revisar mensualmente

| Métrica | Cómo calcular | Objetivo |
|---|---|---|
| **Clientes activos** | Total clientes con `is_active=true` | Crecimiento mes a mes |
| **Tasa de retención** | Clientes que compraron este mes / compraron mes pasado | > 60% |
| **Ticket promedio** | Total ventas / cantidad ventas | Estable o creciente |
| **% clientes con CUIT válido** | Clientes con `document` válido / total | > 80% |
| **% clientes con teléfono** | Clientes con `phone` no nulo / total | > 70% |
| **Saldo pendiente total** | Suma de cuentas corrientes | < 10% facturación mensual |
| **Días promedio de cobro** | Promedio días entre venta crédito y pago | < 30 días |

---

## 9. Solución de problemas frecuentes

### "No puedo ver a un cliente que sé que existe"

**Posibles causas:**

1. **Filtro activo:** Verificá si tenés filtro **Inactivos** o **Activos** seleccionado → cambiá a **Todos**
2. **Otro local:** El cliente puede estar registrado en otro local del grupo → buscalo en **Clientes Globales**
3. **Desactivado:** El cliente puede estar con `is_active=false` → filtrá **Inactivos**

### "No puedo crear un cliente con un CUIT que ya existe"

**Causa:** El sistema previene duplicados con CUIT/DNI iguales.

**Solución:**
- Si es el mismo cliente: editá el existente en vez de crear uno nuevo
- Si son personas distintas con CUIT igual (imposible legalmente): contactar soporte técnico

### "No puedo registrar una venta a crédito"

**Posibles causas:**

1. **Cliente sin CUIT/DNI:** Solo clientes en GlobalClient pueden tener crédito → completar documento
2. **Límite de crédito superado:** El monto supera el límite → ajustar límite o cobrar parte al contado
3. **Cliente moroso:** Tiene deuda vencida — bloqueo automático

### "El cliente apareció con datos mezclados de otro local"

**Causa:** Posiblemente promoción a GlobalClient con merge conflict.

**Solución:** Contactar al equipo técnico — hay un sistema de `field-pick` (Phase 25 REQ-25-05) que resuelve conflictos manualmente.

### "Subí un CSV pero algunos clientes no aparecen"

**Posibles causas:**

1. **CUIT/DNI inválido:** Sin documento válido, no se sube a GlobalClient (sí queda en legacy)
2. **Duplicados saltados:** El sistema saltea filas idénticas
3. **Errores de formato:** Revisar la sección "Errores" del resultado

**Verificación:**
- Ver el historial de cargas (**ClienteVista → Historial**)
- Filtrar por la carga reciente y revisar errores

### "WhatsApp no funciona" → Ver guía específica

📄 [Guía WhatsApp Click-to-Chat - Sección Solución de problemas](./whatsapp-click-to-chat-guia.md#-solución-de-problemas)

### "El reporte de créditos muestra montos extraños"

**Posibles causas:**

1. **Filtros activos:** Verificar rango de fechas y sucursal seleccionada
2. **Pagos parciales no registrados:** Verificar que todos los pagos del mes estén registrados
3. **Moneda:** Confirmar que el reporte está en pesos argentinos (no dólares)

---

## 📞 Soporte

| Tipo | Contacto |
|---|---|
| Bug / error técnico | `marcoskim@gmail.com` |
| Sugerencias de mejora | `marcoskim@gmail.com` |
| Capacitación de empleados | Coordinar con el admin del local |
| Privacidad / datos personales | Ley 25.326 — contactar admin del local |

---

## 📋 Historial de versiones

| Fecha | Versión | Cambios principales |
|---|---|---|
| 2026-03-31 | Phase 25 | 3 niveles de cliente (clients/global/store) + promote/merge |
| 2026-04-15 | Phase 25 Wave 5 | Carga masiva + historial de imports |
| 2026-05-02 | Phase 26 | Crédito · Seña · Favor (cuenta corriente) |
| 2026-05-13 | Phase 29 Wave B | **WhatsApp Click-to-Chat** — esta versión |

---

**Equipo Ventago** — *Tu sistema POS/ERP completo* 💛
