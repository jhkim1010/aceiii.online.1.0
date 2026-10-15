# Phase 111 — Discussion Log (2026-10-14)

Sólo para referencia humana; los agentes leen `111-CONTEXT.md`.

## Mockup
- v1 (7 pantallas) → CODEX 1ª ronda: 8 observaciones (escanear lejos del pulgar, grilla propensa a errores,
  variantes agrupadas en una fila, datos fiscales contradictorios, cobro no auditable, se podía salir sin facturar,
  stock sin deshacer, métricas mezcladas) → todas aplicadas en v2 (10 pantallas).
- CODEX 2ª ronda: 3 graves — cobro incierto (aplicado), stock agotado por otra caja (aplicado),
  devoluciones/NC (fuera de alcance → diferido).

## Preguntas y respuestas
| Área | Pregunta | Opciones | Elegido |
|---|---|---|---|
| Base | ¿Sobre qué app? | mobile-sales-app (rec.) / tienda-admin-app / nueva | **Nueva** |
| Terminal | (usuario) «¿y si la app funciona como una terminal nueva?» | — | Adoptado |
| Caja | ¿A qué cajón va el dinero del celular? | caja existente (rec.) / caja móvil propia / la tienda elige | **Caja existente** |
| Registro | ¿Cómo se registra el celular? | aprobación del encargado (rec.) / la vendedora elige | **Aprobación del encargado** |
| Roles | ¿Quién puede qué? | mismos permisos web (rec.) / fijo por rol | **Mismos permisos web** |
| Cobro | ¿Medios de pago? | igual que POS web (rec.) / sólo efectivo y transferencia | **Igual que POS web** |
| Envío | ¿Cómo se envía la factura? | compartir del celular (rec.) / servidor / ambos | **Compartir del celular** |
| Impresión | ¿Comandera? | sólo con botón (rec.) / no / bluetooth | **Sólo con botón** |
| Plataforma | ¿Qué celulares? | Android (rec.) / Android + iPhone | **Android + iPhone** |
| Alcance | ¿Devoluciones/anulación/NC? | no (rec.) / sólo anular / todo | **No** |
| Reportes | ¿Cuáles? (múltiple) | día / caja / stock-más vendidos / todos | **Día, caja, stock-más vendidos** |
| Offline | ¿Cobrar sin conexión? | no, sólo guardar carrito (rec.) / ventas offline | **No** |

## Hecho verificado durante la discusión
- El login móvil ya no toca `active_sessions` (Phase 37 D-06, `mobile-auth.service.ts:10`): no hay choque de sesión con el POS de la PC.
