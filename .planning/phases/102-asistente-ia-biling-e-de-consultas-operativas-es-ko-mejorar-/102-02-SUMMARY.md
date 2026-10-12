---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 02
subsystem: api-ventago/chat
tags: [ollama, streaming, ndjson, asistente]
requires: []
provides:
  - PuertaDeStream, recortarAUltimaFrase, respuestaCortada, PROMPT_TRADUCIR_KO_ES
  - OllamaProvider.generateStream / completar / modelo
  - LLMFactory.generateStream / completar / modelo()
affects: [102-06, 102-07]
key-files:
  modified:
    - api-ventago/src/app/chat/asistente-reglas.ts
    - api-ventago/src/app/chat/asistente-reglas.spec.ts
    - api-ventago/src/app/chat/llm/ollama.provider.ts
    - api-ventago/src/app/chat/llm/ollama.provider.spec.ts
    - api-ventago/src/app/chat/llm/llm-provider.interface.ts
    - api-ventago/src/app/chat/llm/llm.factory.ts
decisions:
  - "Timeout por defecto de Ollama 120 s -> 60 s (D-02)"
  - "num_predict ko por defecto 250 (OLLAMA_NUM_PREDICT_KO), a confirmar en plan 08"
  - "Referencia de consulta C-<id> es solo referencia, no toca el flujo HMAC de soporte"
metrics:
  tasks: 2
  commits: "api-ventago 12499c40, 3c4c9fd0"
  completed: 2026-10-12
---

# Phase 102 Plan 02: Streaming con compuerta y deadline 60 s Summary

Compuerta de prefijo que nunca emite NO_ENCONTRADO, recorte a la ultima frase completa con aviso y referencia `C-<id>` al vencer el tope, y `OllamaProvider.generateStream` (NDJSON, deadline 60 s, abort externo) con `completar()` para la traduccion ko->es.

## Commits (api-ventago, nada pusheado)
- 12499c40 reglas puras (Task 1)
- 3c4c9fd0 provider + factory (Task 2)

## Verificacion
- `npx jest src/app/chat` : 109 passed (23 en asistente-reglas, 12 en ollama.provider.spec); tsc exit 0; eslint de los 6 archivos limpio.
- Mutacion Task 1: PuertaDeStream con el chequeo de prefijo desactivado -> fallan 4 tests por valor emitido ("No lo encuentro en los manuales" salia). Revertido.
- Mutacion Task 2: sin buffer de lineas (`resto = ''`) -> falla el test de NDJSON partido. Revertido.
- `chat.service.ts` no se toco; `codigoSoporteDe(respuestaCortada(...)) === null` verificado en es y ko.

## Deviations from Plan
- [Rule 3] `recortarAUltimaFrase` ignora la numeracion "1." / "2." al inicio de linea como fin de frase (sin eso el caso `'1. Abrí Stock\n2. Elegí la suc'` devolvia `...\n2.`).
- [Rule 1] En PuertaDeStream se comprueba "buffer empieza con marca completa" antes que "marca empieza con buffer", para suprimir la frase completa "No lo encuentro en los manuales" (un test lo detecto).
- ollama.provider.ts lleva un `eslint-disable` de reglas no-unsafe-* en la cabecera (el archivo ya tenia `error: any` que las incumplia).

## Known Stubs
None.

## Self-Check: PASSED
