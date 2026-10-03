# VentaGO Pedidos

App de escritorio (Windows + macOS) para el **personal de Ventago** (superadmin@app · agent@app):
bandeja de «Pedidos de tiendas» con notificaciones del sistema, y la lista de Tiendas.
Las tiendas siguen usando la web.

- Sesión: token de dispositivo (90 días, revocable). Nunca guarda la contraseña.
- Correr en desarrollo: `../node_modules/electron/dist/Electron.app/Contents/MacOS/Electron .` (sin `NODE_OPTIONS`)
- Instalar en esta Mac: `./scripts/install-mac.sh` → `/Applications/VentaGO Pedidos.app`
- Instaladores: tag `pedidos-app-vX.Y.Z` → GitHub Actions (artifacts `pedidos-app-windows` / `pedidos-app-macos`)
- ★ No correr electron-builder local (poda node_modules de la raíz).
- Tests: `node test/logic.test.js`
