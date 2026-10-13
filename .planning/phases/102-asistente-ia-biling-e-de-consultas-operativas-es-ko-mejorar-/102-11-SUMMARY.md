---
phase: 102-asistente-ia-biling-e-de-consultas-operativas-es-ko-mejorar-
plan: 11
subsystem: api-ventago / chat / knowledge + scripts
tags: [refuerzo, fusion-nocturna, launchd]
requires: [102-05, 102-07, 102-10]
provides: [fusionarEnManual, fusion-refuerzos.cli, scripts/asistente-fusion]
key-files:
  created:
    - api-ventago/src/app/chat/knowledge/fusion-refuerzos.ts
    - api-ventago/src/app/chat/knowledge/fusion-refuerzos.spec.ts
    - api-ventago/src/app/chat/knowledge/fusion-refuerzos.cli.ts
    - scripts/asistente-fusion/fusion-refuerzos.sh
    - scripts/asistente-fusion/prompt.md
    - scripts/asistente-fusion/com.ventago.asistente-fusion.plist
requirements-completed: [D-10, D-10b, D-12, D-14, D-17]
metrics:
  completed: 2026-10-12
---

# Phase 102 Plan 11: Fusion nocturna de refuerzos Summary

Funcion pura e idempotente que agrega los refuerzos activos a los manuales (slug = slugify(titulo), para que el sync del plan 10 los retire), un CLI, y un script nocturno con guardias mas plist launchd, todo sin instalar ni pushear.

## Commits
- api-ventago f0c65260: fusionarEnManual + spec (7 tests) + CLI
- repo raiz 50cc17a: fusion-refuerzos.sh, prompt.md, plist

## Verificacion
- jest fusion-refuerzos 7/7; tsc 0; eslint --max-warnings=0 limpio.
- Mutacion: quitar el chequeo `ya_existe` hizo fallar el test de idempotencia; revertida (7/7).
- `bash -n` OK, `plutil -lint` OK. grep: `set -e` 0, `add -A` 0, `solo=rechazo` 1.
- Dry-run con fixture (FORZAR_HORA=22, --desde-json): jest de eval+knowledge 112 tests verdes, el diff mostro `## Prueba de fusion` en manual_ventas.md, sin commit, sin Telegram. Se restauro solo manual_ventas.md; `manuales/` quedo limpio.
- El script omite el paso D-12 en dry-run (sin --con-eval): la eval con modelo y el flujo de commit/push/build/Telegram NO se ejecutaron nunca (solo `bash -n`).

## Pasos de instalacion pendientes (deploy, plan 13)
1. Aplicar la migracion knowledge_refuerzos en produccion (plan 12) y desplegar el codigo antes de instalar.
2. Crear `~/.config/ventago/asistente-fusion.env` (chmod 600) con TELEGRAM_PEDIDOS_BOT_TOKEN y TELEGRAM_PEDIDOS_CHAT_ID; probar con `scripts/asistente-fusion/fusion-refuerzos.sh --probar-aviso "prueba"`.
3. Copiar el plist a `~/Library/LaunchAgents/` y `launchctl bootstrap gui/$(id -u) ...` (NO hecho aqui).
4. Revisar los flags de `claude -p` del plist (`--permission-mode`, `--allowedTools`) contra la version instalada de claude; no se probaron.

## Deviations from Plan
- [Rule 1] eslint --fix (solo en los 3 archivos nuevos) y tipado de `JSON.parse` en el CLI por no-unsafe-assignment.
- El plist usa `/bin/bash -lc` para expandir `$HOME` y leer prompt.md; no hay binario/flags de bot de Pedidos que copiar (ese bot es Python, no claude).
- Las comprobaciones de build por SHA y retiro usan ssh a Jenkins (build.xml `<result>`), sin probar contra el servidor.

## Known Stubs
Ninguno.

## Self-Check: PASSED
