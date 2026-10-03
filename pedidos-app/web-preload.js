// Ventana web DENTRO de la app (legacy · factura electrónica): entra ya logueada.
//
// ★ Corre antes que los scripts de la página, en cada carga. Pide al proceso principal la
//   sesión a inyectar (JWT recién refrescado + userData + tienda «actuar como») y la pone donde
//   la web la busca: localStorage accessToken/userData, sessionStorage ventago_acting_store.
// ★ No expone nada a la página (sin contextBridge): la web sigue siendo la web.
const { ipcRenderer } = require('electron');

try {
  const s = ipcRenderer.sendSync('web-sesion', location.origin);
  if (s && s.token) {
    localStorage.setItem('accessToken', s.token);
    if (s.userData) localStorage.setItem('userData', JSON.stringify(s.userData));
    if (s.acting) sessionStorage.setItem('ventago_acting_store', JSON.stringify(s.acting));
    else sessionStorage.removeItem('ventago_acting_store');
  }
} catch {
  // sin sesión: la web muestra su login
}
