# 📱 Guía de uso — WhatsApp Click-to-Chat

**Versión:** Phase 29 Wave B
**Fecha:** 2026-05-13
**Aplicación:** Ventago POS/ERP

---

## 📖 ¿Qué es WhatsApp Click-to-Chat?

Es una nueva función de Ventago que permite enviar mensajes de WhatsApp a tus clientes con un solo click, **usando el número del administrador del local como remitente**. El cliente recibe el mensaje como si viniera directamente del dueño/admin del local.

### ¿Por qué es útil?

- ✅ **Costo $0** — Sin APIs pagas ni servicios externos
- ✅ **Sin riesgo de bloqueo** — Usa WhatsApp Web oficial
- ✅ **5 plantillas listas para usar** — Cumpleaños, créditos, recordatorios, etc.
- ✅ **Registro automático** — Todo envío queda guardado para consulta posterior
- ✅ **Identidad consistente** — Siempre se envía desde el número del admin del local

### ¿Cómo funciona?

1. Hacés click en el botón verde de WhatsApp al lado de un cliente
2. Elegís una plantilla (ej. saludo de cumpleaños)
3. Completás las variables (código de promo, monto, etc.)
4. Se abre automáticamente WhatsApp Web con el mensaje listo
5. Solo tenés que apretar [Enviar] en WhatsApp Web

---

## ⚙️ Configuración inicial (una sola vez)

### Paso 1: Acceder a la configuración

Desde el menú lateral:

```
Configuración → WhatsApp
```

Ruta directa: `https://ventago.coolsistema.com/configuracion/whatsapp`

### Paso 2: Registrar tu número personal de WhatsApp

> ⚠️ **Importante:** Este paso lo debe hacer **cada admin de su propia cuenta**, no otro usuario. Es información personal.

1. En la sección **"1. Tu número de WhatsApp"**, escribí tu número
2. Formatos aceptados:
   - Internacional: `+54 9 11 4567-8901` (recomendado)
   - Nacional: `11 4567-8901`
   - Móvil: `15-4567-8901`
3. Hacé click en **[Guardar]**
4. El sistema normaliza automáticamente al formato internacional **E.164** (`+5491145678901`)
5. Vas a ver el mensaje: *"Número registrado: +54..."*

**¿Qué pasa si me equivoco?** No hay problema — podés sobrescribir cuantas veces quieras, o dejarlo vacío para borrarlo.

### Paso 3: Designar al representante del local

> 👑 Solo un admin con permisos puede hacer este paso.

1. En la sección **"2. Representante de WhatsApp del local"**, abrí el desplegable
2. Vas a ver la lista de admins del local que **ya registraron su número** (los que no lo hicieron, no aparecen)
3. Seleccioná uno y hacé click en **[Aplicar]**
4. Vas a ver el cartel verde: *"Representante actual: [Nombre] — +54..."*

**¿Por qué solo uno?** Para que el cliente reciba mensajes siempre desde el mismo número del local. Si dos admins enviaran desde números distintos, el cliente se confundiría.

### Paso 4: Login en WhatsApp Web

> 💡 **Este paso es crítico** — el sistema NO puede hacerlo por vos.

En la computadora donde vas a usar Ventago:

1. Abrí https://web.whatsapp.com en otra pestaña del navegador
2. Escaneá el código QR con el **WhatsApp del teléfono del representante**
3. Mantené la sesión abierta durante el horario de atención

> ❌ **Si la sesión está cerrada o pertenece a otro número**, los clientes recibirán mensajes desde un número distinto al esperado.

---

## 🚀 Cómo enviar un mensaje (uso diario)

### Paso 1: Buscar al cliente

Desde el menú lateral:

```
ClienteVista
```

Buscá al cliente por nombre, documento, teléfono o email.

### Paso 2: Hacer click en el botón de WhatsApp

En la fila del cliente, hay tres íconos a la derecha:

| Ícono | Función |
|---|---|
| 🟢 **WhatsApp** | Enviar mensaje |
| ✏️ Lápiz | Editar cliente |
| 🗑️ Tacho | Desactivar cliente |

> 💡 El botón de WhatsApp aparece **gris (deshabilitado)** si:
> - El cliente no tiene teléfono registrado
> - El cliente está inactivo

### Paso 3: Elegir una plantilla

Se abre un diálogo con **5 plantillas disponibles**:

#### 🎂 Saludo de cumpleaños (Marketing)
> *"¡Feliz cumpleaños [Nombre]! 🎉 En tu día especial te regalamos un *15% OFF* en toda la tienda. 🎁 Código: *[CÓDIGO]* 📍 Válido por 7 días..."*

**Variables a completar:**
- `promoCode` — Código de descuento (ej. `CUMPLE-2026`)

#### ⚠️ Recordatorio de crédito (Utility)
> *"Hola [Nombre], te recordamos que tienes un saldo pendiente de *$[MONTO]* con vencimiento el [FECHA]..."*

**Variables a completar:**
- `deuda` — Monto adeudado (ej. `24500`)
- `dueDate` — Fecha de vencimiento (ej. `20/05/2026`)

#### 💔 Te extrañamos / Cliente inactivo 60+ días (Marketing)
> *"[Nombre], ¡hace tiempo que no te vemos! Tu última visita fue el [FECHA]. Como te extrañamos, te invitamos con un *10% OFF* en tu próxima compra. 🎁..."*

**Variables a completar:**
- `lastVisitDate` — Fecha de última visita (ej. `2026-03-15`)

#### 🆕 Anuncio de nuevo producto (Marketing)
> *"¡Hola [Nombre]! Acaba de llegar *[PRODUCTO]* y pensamos que te puede interesar..."*

**Variables a completar:**
- `productName` — Nombre del producto (ej. `Pollo entero kg`)

#### 🧾 Reenvío de comprobante (Utility)
> *"Hola [Nombre], aquí está la información de tu compra: 🧾 Comprobante: #[ID] 📅 Fecha: [FECHA] 💰 Total: $[TOTAL]..."*

**Variables a completar:**
- `saleId` — ID de la venta (ej. `V-8742`)
- `total` — Total de la venta (ej. `18400`)
- `date` — Fecha de la venta (ej. `08/05/2026`)

> 💡 **Variables automáticas:** `fullname` (nombre del cliente) y `storeName` (nombre del local) se completan automáticamente — no necesitás escribirlas.

### Paso 4: Completar las variables

El diálogo te muestra los campos que faltan completar. Los placeholders (texto gris) te dan ejemplos:

```
┌─────────────────────────────────────┐
│ promoCode                            │
│ ┌─────────────────────────────────┐ │
│ │ CUMPLE-2026                     │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### Paso 5: Verificar la vista previa

Antes de enviar, el diálogo muestra el mensaje completo con los valores reales:

```
┌─────────────────────────────────────┐
│ 3. Vista previa                     │
│ ┌─────────────────────────────────┐ │
│ │ ¡Feliz cumpleaños María! 🎉    │ │
│ │                                 │ │
│ │ En tu día especial te          │ │
│ │ regalamos un *15% OFF* en      │ │
│ │ toda la tienda.                 │ │
│ │                                 │ │
│ │ 🎁 Código: *CUMPLE-2026*       │ │
│ │ ...                             │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

✅ **Si la vista previa se ve bien**, hacé click en **[Abrir WhatsApp]**.

### Paso 6: Enviar desde WhatsApp Web

Se abre **una nueva pestaña del navegador** con WhatsApp Web:

- El chat del cliente ya está abierto
- El mensaje ya está escrito en el cuadro de texto
- **Solo tenés que apretar el botón verde [Enviar]** ▶️

> ⚠️ **Importante:** Si no apretás [Enviar] en WhatsApp Web, el mensaje NO se envía. Ventago solo prepara el link.

---

## 🔍 ¿Cómo verificar que el envío quedó registrado?

Cada vez que generás un link, Ventago guarda automáticamente:

| Campo | Significado |
|---|---|
| Cliente | A quién se le mandó |
| Plantilla | Qué tipo de mensaje |
| Quien hizo click | Usuario de Ventago que abrió el link |
| Número remitente | WhatsApp del representante del local |
| Fecha y hora | Momento de generación del link |
| Estado | `link_generated` (link creado correctamente) |

Esta información se usará en próximas versiones para:
- **Cliente 360** — Ver historial completo de cada cliente
- **Métricas de campañas** — Cuántos clientes contactamos este mes
- **Atribución de ventas** — Si el cliente volvió después del mensaje

---

## ❓ Preguntas frecuentes

### ¿El cliente sabe que el mensaje vino de Ventago?

No. El cliente recibe el mensaje **como si vos (el admin) se lo escribieras desde tu teléfono**. Para el cliente es indistinguible de un mensaje personal. Esto es bueno porque genera más confianza y mejor tasa de respuesta.

### ¿Puedo personalizar el mensaje antes de enviar?

Sí. Cuando se abre WhatsApp Web, el mensaje aparece en el cuadro de texto pero **podés editarlo** antes de apretar [Enviar]. Cambiá lo que quieras.

### ¿Qué pasa si me olvido de apretar [Enviar] en WhatsApp Web?

El link queda registrado en Ventago como `link_generated`, pero el mensaje **no se envía al cliente**. Es un comportamiento intencional — vos tenés el control final.

### ¿Puedo enviar mensajes masivos a varios clientes?

> ⏳ **Aún no.** Esta función (envío masivo por segmento) está prevista para **Wave C**.

Por ahora se envía uno por uno. Si necesitás avisar a 30 clientes, tenés que hacer 30 clicks.

### ¿Y si el cliente tiene varios teléfonos?

Ventago usa el campo `phone` del cliente. Si tiene varios, editá el cliente primero y dejá el correcto.

### ¿Puedo cambiar el representante del local?

Sí, en cualquier momento. **Configuración → WhatsApp → "2. Representante"** → elegí otro → [Aplicar].

> ⚠️ Recordá que también tenés que cerrar sesión en WhatsApp Web y volver a entrar con el QR del nuevo representante.

### ¿Qué pasa si el representante renuncia?

1. Entrá a **Configuración → WhatsApp**
2. Cambiá el representante a otro admin disponible
3. El admin que renunció puede **borrar su propio número** desde su perfil (campo `whatsappPhone` vacío + Guardar)
4. Cerrar sesión en WhatsApp Web

### ¿Puedo crear mis propias plantillas?

> ⏳ **Aún no.** Las 5 plantillas actuales están en el código del sistema. Crear plantillas personalizadas por local está previsto para **Wave C**.

Si tenés sugerencias de plantillas útiles, escribímelas y las incorporo a futuras versiones.

### ¿Los empleados (vendedores) pueden enviar mensajes?

Sí. Los roles `admin`, `superadmin`, `gerente` y `vendedor` pueden usar el botón de WhatsApp. Pero el mensaje **siempre se envía desde el número del representante** (no del empleado que hizo click).

### ¿Cómo se ve esto en el log de auditoría?

Cada envío queda registrado en:
- **Tabla `whatsapp_messages`** — Detalle completo
- **Tabla `audit_logs`** — Registro de la acción

Si necesitás consultar quién mandó qué, podés pedirlo al equipo técnico.

---

## 🚨 Solución de problemas

### "El botón de WhatsApp está gris (deshabilitado)"

**Causa:** El cliente no tiene teléfono registrado, o está inactivo.

**Solución:** Editar al cliente y agregar el teléfono.

---

### "Apareció el cartel: *Representante de WhatsApp no configurado*"

**Causa:** Nadie designó al representante del local en Configuración.

**Solución:** Ir a **Configuración → WhatsApp → "2. Representante"** y elegir uno.

---

### "Apareció el cartel: *El representante no tiene número de WhatsApp registrado*"

**Causa:** El representante designado nunca registró su número personal.

**Solución:** El representante debe iniciar sesión y entrar a **Configuración → WhatsApp → "1. Tu número"** para registrarlo.

---

### "Apareció el cartel: *Teléfono del cliente no es válido*"

**Causa:** El teléfono del cliente no se puede normalizar a formato internacional (E.164).

**Solución:** Editar al cliente y corregir el teléfono. Formatos válidos:
- `+54 9 11 4567-8901`
- `11 4567-8901`
- `15-4567-8901`

---

### "Se abre WhatsApp Web pero pide escanear el QR"

**Causa:** La sesión de WhatsApp Web en tu computadora está cerrada.

**Solución:** Escaneá el QR con el teléfono del **representante del local** (no tu teléfono personal si sos otro empleado).

---

### "El mensaje se está enviando desde un número incorrecto"

**Causa:** En tu computadora, WhatsApp Web está logueado con un número distinto al del representante designado.

**Solución:**
1. Cerrá sesión en https://web.whatsapp.com
2. Escaneá el QR con el teléfono del representante correcto
3. Volvé a probar

---

### "Apareció toast de error que no entiendo"

Códigos de error comunes:

| Código | Significado | Solución |
|---|---|---|
| `REPRESENTATIVE_NOT_SET` | Falta designar representante | Configuración → WhatsApp |
| `REPRESENTATIVE_PHONE_MISSING` | Representante sin número | El admin debe registrar su número |
| `INVALID_CLIENT_PHONE` | Teléfono del cliente inválido | Editar cliente, corregir teléfono |
| `CLIENT_PHONE_MISSING` | Cliente sin teléfono | Editar cliente, agregar teléfono |
| `UNKNOWN_TEMPLATE` | Plantilla no encontrada | Reportar al equipo técnico |
| `INVALID_PHONE` | Tu número personal inválido | Reintentá con formato `+54 9 11...` |
| `TARGET_PHONE_MISSING` | Usuario seleccionado como representante no tiene número | El usuario debe registrar su número primero |

---

## 🛡️ Consideraciones de privacidad

### Información personal del admin

El número de WhatsApp registrado en tu perfil:

- ✅ Solo **vos** podés ver, editar o borrar tu propio número
- ✅ El admin del local lo ve cuando aparecés en la lista de candidatos
- ❌ Los empleados (vendedores) **NO** ven tu número personal
- ❌ Los clientes **NO** ven tu número directamente (solo si les enviaste mensajes)

### Cuando renuncia un empleado

1. El representante (admin del local) cambia el representante de WhatsApp a otro admin
2. El admin que renuncia **borra su propio número** (campo vacío + Guardar)
3. Audit log queda registrado

### Protección de datos del cliente

Los teléfonos de los clientes están sujetos a la ley argentina **25.326 de Protección de Datos Personales**. No compartas estos teléfonos fuera del sistema Ventago.

---

## 🗺️ Próximas funcionalidades (roadmap)

### Wave C — Próximos meses (sujeto a prioridades)

- 📅 **Envío automático de cumpleaños** — El sistema manda solo a los clientes que cumplen años hoy
- 📅 **Recordatorios de crédito automáticos** — Cuando se acerca la fecha de vencimiento
- 📅 **Re-engagement de clientes inactivos** — Cron diario detecta clientes 60+ días inactivos
- 📅 **Plantillas personalizadas por local** — Crear tus propias plantillas
- 📅 **Envío masivo por segmento** — VIP, deudores, etc.
- 📅 **Métricas de campañas** — Cuántos respondieron, cuántos volvieron a comprar

### Wave A — Cliente 360 (también próximo)

- 📅 **Vista 360 del cliente** — Historial de compras, mensajes, créditos, todo en una sola pantalla
- 📅 **Segmentación RFM** — VIP / Leales / Regulares / En riesgo / Dormidos
- 📅 **Tags y cumpleaños** — Etiquetas personalizadas + alertas de cumpleaños

---

## 📞 Soporte

Si tenés dudas o encontrás un bug:

- 📧 Email: `marcoskim@gmail.com`
- 🐛 Reportar bug: incluir captura de pantalla + paso a paso para reproducir
- 💡 Sugerencias: bienvenidas para mejorar las plantillas o el flujo

---

## 📝 Historial de cambios

| Fecha | Versión | Cambios |
|---|---|---|
| 2026-05-13 | Phase 29 Wave B | Lanzamiento inicial — Click-to-Chat con 5 plantillas |

---

**Equipo Ventago** — *Tu POS/ERP de confianza*
