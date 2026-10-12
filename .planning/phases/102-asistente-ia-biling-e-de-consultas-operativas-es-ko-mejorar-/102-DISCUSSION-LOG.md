# Phase 102: Asistente IA bilingüe (es/ko) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 102-asistente-ia-bilingue-de-consultas-operativas-es-ko
**Areas discussed:** Modelo y costo, Respuesta en coreano, Refuerzo de manuales, Meta y prueba

---

## Modelo y costo

| Option | Selected |
|---|---|
| API paga (Claude Haiku) — recomendado | |
| Ollama, modelo más grande | ✓ |
| qwen2.5:3b igual | |

Tiempo de respuesta: **60 s + streaming** ✓ (vs 30 s / sin límite).
Si srv2 no alcanza: **parar y reportar** ✓ (vs quedarse en 3b).

## Respuesta en coreano

Quién pregunta en coreano: **dueño/administrador coreano** ✓ (vs empleados / ambos).
Base de la respuesta: **un solo manual en español** ✓ (vs manual coreano aparte / sólo temas principales).
Nombres de pantallas: sin preferencia → Claude decide (español tal cual).
`soporte_remoto_ko.md`: **dejarlo** ✓ (vs fusionar y borrar — recomendado).

## Refuerzo de manuales

Autor: **borrador Claude → revisión del usuario** ✓.
Prioridad: **preguntas reales sin respuesta primero** ✓.
Mensaje del usuario a mitad de la discusión: «Ai를 위한 스페인어 매뉴얼을 때마다 보강할 수 있는 쉬운 방법이 잇으면 좋겠어».
Método fácil: **botón «Responder» en Preguntas sin respuesta** ✓ (vs responder por Telegram / .md + sesión Claude).
Dónde se guarda: **DB primero, fusión nocturna al .md** ✓ (vs DB como original).

## Meta y prueba

Criterio de fin: **preguntas reales de producción** ✓ (vs 90 % + inventar 0 / 28/31). Luego: **el usuario lee la tabla y decide** ✓.
Inventar: **0, bloquea el deploy** ✓.
Preguntas en coreano: **las de español también en coreano (~60)** ✓.

## Claude's Discretion
- Nombres de pantalla en respuestas coreanas; modelo exacto; mecanismo de términos ko→es y de reescritura.

## Deferred Ideas
- Consultas de datos por IA; agregados vía Telegram; API paga.
