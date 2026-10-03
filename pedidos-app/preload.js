// Puente mínimo: el renderer no tiene Node ni el token — sólo estos llamados.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pedidos', {
  sesion: () => ipcRenderer.invoke('sesion'),
  login: (u, p) => ipcRenderer.invoke('login', u, p),
  logout: () => ipcRenderer.invoke('logout'),
  api: (metodo, ruta, body) => ipcRenderer.invoke('api', metodo, ruta, body),
  responder: (id, texto, fotos) => ipcRenderer.invoke('responder', id, texto, fotos),
  foto: (id, mensajeId, idx) => ipcRenderer.invoke('foto', id, mensajeId, idx),
  abrirWeb: (ruta, tienda, titulo) => ipcRenderer.invoke('abrir-web', ruta, tienda, titulo),
  cerrarWeb: () => ipcRenderer.invoke('cerrar-web'),
  info: () => ipcRenderer.invoke('info'),
  on: (canal, fn) => {
    if (!['sesion', 'abrir-pedido', 'bandeja-cambio', 'conexion', 'web-abierta', 'web-cerrada', 'web-titulo'].includes(canal)) return;
    ipcRenderer.on(canal, (_e, dato) => fn(dato));
  },
});
