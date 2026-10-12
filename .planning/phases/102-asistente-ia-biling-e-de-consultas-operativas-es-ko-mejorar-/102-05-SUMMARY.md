---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 05
subsystem: chat/eval
tags: [asistente, evaluacion, ko-es, compuerta]
requires: ["102-01"]
provides:
  - "juicio.ts: juzgar / resumir / codigoSalida / enHorarioDeTiendas / expandirPreguntas"
  - "Prueba fija de 60 filas (31 es/ko base + 29 variantes ko)"
  - "evaluar-asistente con exit 1 si inventa, guardia de horario, --idioma/--solo/--salida/--ignorar-horario"
affects: [api-ventago/src/app/chat/eval]
key-files:
  created:
    - api-ventago/src/app/chat/eval/juicio.ts
    - api-ventago/src/app/chat/eval/juicio.spec.ts
  modified:
    - api-ventago/src/app/chat/eval/preguntas-asistente.ts
    - api-ventago/src/app/chat/eval/preguntas-asistente.spec.ts
    - api-ventago/src/app/chat/eval/evaluar-asistente.ts
    - api-ventago/src/app/chat/knowledge/terminos-ko-es.ts
decisions:
  - "MINIMO_ACIERTOS_ES = 17 (no 19): el 19/28 anterior incluía 2 preguntas ko de soporte remoto, que ahora cuentan en ko"
  - "MINIMO_ACIERTOS_KO = 18"
metrics:
  completed: 2026-10-12
  tasks: 2
---

# Phase 102 Plan 05: Prueba fija es/ko y compuerta «inventa = 0» Summary

Prueba fija ampliada a 60 filas con variantes coreanas naturales, búsqueda medida por idioma con mínimos propios, y `evaluar-asistente` que sale con código 1 si algo «inventa» y se niega a correr en horario de tiendas.

## Commits (api-ventago, sin push)
- 1e8e6324: juicio.ts puro + spec (15 tests) + campo `ko` en la interfaz
- 21c4b5cf: 29 variantes ko, spec por idioma, evaluar-asistente con flags, +2 entradas en la tabla ko→es

## Mediciones de búsqueda (sin modelo)
- es 17/26, ko 18/28 (con la tabla). Sin la tabla (control: expandirKo anulado) ko cae a 2/28 y el test falla, así que el umbral sí depende de la tabla.
- Fallos es: pago mixto, venta en espera, devolver seña, «fiar», «cargar artículo», stock por local, mandar mercadería, coser en taller, rollos de tela.
- Fallos ko (10): 판매 시작, 카드+현금, 계약금 환불, 외상값 수금, 맡겨둔 돈, 가격 인상, 매장 간 이동, 봉제 발송, 원단 입력, 화면 지원 요청. Insumo para el plan 09.
- Tabla ampliada: 사진/이미지 -> imagen, foto; 전기/요금/월세 -> gasto, categoria (ko 16 -> 18).

## Verificación
- jest eval + knowledge: 6 suites, 54 tests verdes; tsc exit 0; eslint limpio.
- Mutación: `codigoSalida` que devuelve siempre 0 -> falla el test inventa=1 (revertida).
- Primer intento de control con sed rompió la compilación (Tests: 0, no válido); se repitió con un cambio de tipos correcto.
- NO ejecutada la evaluación con modelo (Ollama no usado; además son las 20:21 ART, y el plan pide correrla en planes 08/12/15). Guardia de horario probada sólo en la función pura.

## Deviations from Plan
1. [Rule 1] MINIMO_ACIERTOS_ES = 17 en vez de «no bajar de 19»: el 19 contaba 2 filas ko; los aciertos es reales eran y siguen siendo 17 (sin regresión).
2. Se añadieron 2 entradas a terminos-ko-es.ts (previsto en el plan) para que ko supere la mitad.

## Known Stubs
None.

## Self-Check: PASSED
