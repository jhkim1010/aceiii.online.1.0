# Resolución — revisión externa del derrame del resto (POS «Pago» en línea)

Informe: `.team/reviews/manual-pos-derrame-codex.md`
Commits: `ventago-app 67b8a25` (funcionalidad) · `ventago-app 8a55d70` (correcciones)

| # | Hallazgo | Severidad dada | Veredicto | Qué se hizo |
|---|---|---|---|---|
| 1 | El derrame cobra de menos si el destino tiene recargo | Alta | **Aceptado** | `motivoPorRecargo` en `pago-inline.ts` bloquea esa fila para teclear y como destino. El criterio sale de `conRecargo` (pago-rapido.ts), ahora exportado |
| 2 | La ✕ no borra el pago (dos `setPaymentMethods` sobre el mismo estado) | Media | **Aceptado — y es más grave que «media»** | Una sola escritura: `quitarYDerramar` |

## Por qué el hallazgo 1 no era teórico

`payment_methods` con `adjust_percent ≠ 0`, medido en **local y en producción** (idénticos):

```
 id |       title        |        slug        | adjust_percent | store_id
 54 | TARJETA DE CREDITO | tarjeta-de-credito |          10.00 |        6
```

La tienda 6 está activa y el cajero puede poner ese método en cualquier ranura desde
el combo. Con el derrame, la plata le llegaba **sola**.

## Por qué el hallazgo 2 es peor que «media»

El informe lo marcó media; en la práctica la ✕ **no hacía nada** cuando la venta ya
estaba paga, y el cajero no tiene forma de notarlo salvo mirando el importe. Es el
control que se usa para corregir un cobro mal cargado.

## Lo que la revisión NO encontró (y coincide con lo medido)

> «No encontré un error aritmético independiente en `derramarResto`: dada una lista
> actualizada y un destino realmente usable, deja la suma exactamente en el total.»

Coincide con los 6 mutantes muertos del primer commit y con la venta 5171441
(Efectivo 5.000 + Banco 16.000 = 21.000).

## Nota de proceso — el hook automático no revisó esto

`.team/reviews/.auto-codex.SKIPPED.20260923-202859.txt` dice `reason=secret_pattern_in_diff`
(líneas 4900 y 8997). El diff acumulado abarcaba muchos commits; **mi** diff tiene 510
líneas, así que la alarma no era de este cambio. Se corrió codex a mano.

★ Además, `codex exec` con el diff entero en el argv **muere en silencio con exit 0 y
  salida vacía**. El grupo de control (prompt corto, y prompt corto que exige leer un
  archivo) sí responde. Lo que funciona: prompt corto que le diga a codex qué leer,
  con `-o <archivo>` para capturar la respuesta final.
