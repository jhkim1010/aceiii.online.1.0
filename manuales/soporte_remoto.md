# Soporte Remoto Embebido (visor en vivo)

<!--
  Manual de uso del Soporte Remoto de Ventago (Phase 41).
  Formato RAG: cada "## Sección" se indexa como documento separado del AI agent.
  Las imágenes son placeholders en texto: reemplazar el bloque ">  🖼️ [Captura: ...]"
  por una imagen real cuando estén disponibles (no romper el formato de secciones).
-->

## Qué es el Soporte Remoto y cómo funciona

El Soporte Remoto permite que un agente del equipo de soporte **vea en vivo la pantalla** del cliente (el operador de la tienda) directamente desde el navegador, para ayudarlo a resolver un problema sin tener que estar físicamente al lado.

Características clave:

- **Solo lectura**: el agente **ve** la pantalla pero **no puede controlar** la computadora del cliente (no puede hacer clic, escribir ni mover archivos). La única señal que envía el agente es un **cursor rojo** para señalar dónde mirar.
- **Sin video**: no se transmite video de la pantalla, sino una réplica del contenido (DOM mirroring con rrweb). Esto consume muy poco internet y casi no tiene retraso.
- **Bajo pedido**: la sesión **solo empieza cuando el cliente la solicita**. Nunca se graba la pantalla sin que el cliente lo pida.
- **Temporal**: cada sesión dura como máximo **15 minutos** y luego se cierra sola.

> 🖼️ [Captura: vista general — pantalla del cliente con banner de soporte arriba y cursor rojo del agente]

## Cómo solicitar soporte (guía del cliente / tienda)

Cuando un agente de soporte te pida iniciar una sesión:

1. Buscá el botón flotante **"Solicitar Soporte"** (ícono de salvavidas 🛟) en la **esquina inferior derecha** de la pantalla.
2. Hacé clic en ese botón.
3. Aparecerá un **banner rojo en la parte superior** que dice *"Soporte remoto solicitado — esperando al agente…"*.
4. El sistema genera un **código de sesión (UUID)**, una cadena larga tipo `a1b2c3d4-....`.

A partir de ese momento tu pantalla queda lista para que el agente se conecte. **La grabación solo empieza cuando vos lo solicitás** — nunca antes.

> 🖼️ [Captura: botón flotante "Solicitar Soporte" en la esquina inferior derecha]

## Cómo compartir el código (UUID) con el equipo de soporte

El **código de sesión (UUID)** es la "llave" que el agente necesita para ver tu pantalla.

1. Una vez solicitado el soporte, comunicá el código al agente por el canal que estés usando (teléfono, WhatsApp, chat).
2. En el entorno de desarrollo, el código se muestra en pequeño abajo a la izquierda (`support:....`). En producción, el agente normalmente lo verá en su panel de **Soporte** si pertenece a tu misma tienda.
3. **No compartas el código con personas ajenas.** Solo el equipo de soporte autorizado debería usarlo.

> ⚠️ Aunque alguien tenga el código, **no puede entrar si no tiene permiso de soporte** en el sistema (ver sección de seguridad).

## Qué significa el cursor rojo en mi pantalla (cliente)

Mientras la sesión está activa, vas a ver un **cursor rojo grande con la etiqueta "Soporte"** moviéndose por tu pantalla.

- Ese cursor lo mueve **el agente de soporte** para señalarte **dónde mirar o dónde hacer clic**.
- **El cursor NO hace clic por vos.** Es solo una guía visual: vos seguís teniendo el control total de tu equipo.
- Si el agente deja de mover el mouse, el cursor desaparece después de unos **3 segundos** y vuelve a aparecer cuando se mueve de nuevo.

Pensalo como si el agente estuviera señalando tu pantalla con el dedo, pero a distancia.

> 🖼️ [Captura: cursor rojo con etiqueta "Soporte" señalando un botón]

## Cómo finalizar la sesión de soporte (cliente)

Tenés el control para terminar la sesión en cualquier momento:

1. En el **banner rojo superior**, hacé clic en el botón **"Finalizar"**.
2. La grabación se detiene de inmediato y el agente deja de ver tu pantalla.

La sesión **también termina automáticamente** en estos casos:

- Pasaron **15 minutos** desde que la iniciaste.
- Cerraste la pestaña o perdiste la conexión a internet.

Después de finalizar, si necesitás más ayuda, simplemente **solicitá soporte de nuevo** (se genera un código nuevo).

## Cómo conectarse como agente de soporte (visor en vivo)

Esta sección es para el **equipo de soporte**. Necesitás tener el permiso **`support.view`** o un rol de administrador.

1. En la barra lateral, abrí **"Soporte en vivo"** (ícono de pantalla compartida).
2. Vas a ver el **panel de sesiones activas** de tu tienda. Cada fila muestra el código, el estado (`waiting`/`active`) y la hora de expiración.
3. Opción A: hacé clic en **"Ver en vivo"** en la sesión que querés atender.
4. Opción B: hacé clic en **"Abrir visor"**, pegá el **código (UUID)** que te pasó el cliente y presioná **"Conectar"**.

> 🖼️ [Captura: panel de Soporte con la lista de sesiones activas y el botón "Ver en vivo"]

## Cómo ver la pantalla del cliente y guiar con el cursor (agente)

Una vez conectado:

- La pantalla del cliente se **reproduce en vivo** en el área negra del visor. Vas a ver lo que el cliente ve, en tiempo real.
- El contador **"eventos recibidos"** confirma que están llegando los cambios de pantalla.
- **Mové tu mouse sobre el área de reproducción**: tu cursor aparece como un **cursor rojo "Soporte"** en la pantalla del cliente. Usalo para señalarle exactamente dónde tocar.
- **No podés hacer clic ni escribir** en el equipo del cliente (es solo lectura). Guialo con la voz + el cursor: *"Tocá el botón que estoy señalando ahora"*.
- Para terminar, hacé clic en **"Finalizar"**.

> 🖼️ [Captura: visor del agente mostrando la pantalla del cliente en vivo]

## Seguridad y privacidad del Soporte Remoto

El sistema está diseñado para proteger los datos sensibles del cliente:

- **Pantallas y datos enmascarados**: todos los campos de texto que se escriben (inputs) se ocultan automáticamente. Las pantallas marcadas como sensibles —**QR de pago de MercadoPago, claves/tokens (AES), contraseñas**— se **bloquean** y el agente no las ve.
- **Cierre automático a los 15 minutos**: ninguna sesión queda abierta indefinidamente.
- **Un solo visor a la vez**: solo **un agente** puede ver una sesión. Si otro intenta entrar, se le rechaza.
- **Aislamiento por tienda**: un agente solo puede ver sesiones de **su propia tienda**. No se puede ver la pantalla de otra tienda aunque se tenga el código.
- **Permiso obligatorio**: el visor exige inicio de sesión + permiso `support.view`. Si el código se filtra, una persona sin permiso **no puede** conectarse.
- **Solo lectura, sin control remoto**: el agente nunca puede operar el equipo del cliente. El cursor rojo es solo una guía visual.

## Preguntas frecuentes (FAQ) del Soporte Remoto

**¿El agente puede controlar mi computadora?**
No. Es **solo lectura**. El agente solo ve la pantalla y mueve un cursor rojo para señalar. No puede hacer clic, escribir ni acceder a tus archivos.

**¿Se ve mi contraseña o el QR de pago?**
No. Los campos de texto se enmascaran y las pantallas sensibles (pagos, claves, contraseñas) se bloquean automáticamente.

**¿Cuánto dura la sesión?**
Máximo **15 minutos**. Después se cierra sola. Podés volver a solicitarla si hace falta.

**¿Pueden conectarse dos agentes a la vez?**
No. Solo **un visor** por sesión.

**¿Necesito instalar algo?**
No. Todo funciona dentro del navegador, en la misma página de Ventago.

**¿Consume mucho internet?**
Muy poco. No se transmite video, sino una réplica liviana del contenido de la pantalla.

**¿El soporte puede entrar sin que yo lo pida?**
No. La sesión **solo empieza cuando vos hacés clic en "Solicitar Soporte"**.

## Solución de problemas del Soporte Remoto

**El agente dice que no ve nada / pantalla en negro:**
- Verificá que el banner rojo superior siga visible (sesión activa).
- Si pasaron más de 15 minutos, la sesión expiró: solicitá soporte de nuevo.
- Refrescá la página y volvé a solicitar soporte.

**"Ya hay un visor activo (máx. 1)":**
- Otro agente ya está conectado a esa sesión. Esperá a que finalice o coordiná con el equipo.

**"No se pudo unir: cross_tenant":**
- El agente pertenece a otra tienda. Solo agentes de la misma tienda pueden ver la sesión.

**"Sin permiso support.view":**
- El usuario no tiene el permiso de soporte. Pedile a un administrador que se lo asigne (o usar un rol de administrador).

**El cursor rojo no aparece:**
- El agente no está moviendo el mouse, o pasaron 3 segundos sin movimiento. Es normal: reaparece al moverse.

**La sesión se cortó sola:**
- Probablemente expiró (15 min) o se perdió la conexión. Solicitá soporte nuevamente.
