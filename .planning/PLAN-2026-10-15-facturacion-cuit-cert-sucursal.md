# Facturación: una tarjeta por CUIT (certificado + PV) · la sucursal elige su emisor (2026-10-15)

Usuario: «admin, config, facturación 에서 사용하는 cuit과 punto de venta 에 대해서 다 정리가 되어 있어야 하고
certificado digital 이 올라가 있게 해야 해. 그리고 sucursal (나중에) 셋팅할 때 이를 선택하는 화면으로 단순화»
Aprobado: «아주 좋아. 그렇게 하자.. 특히 공간 낭비가 없도록 조심해줘.. codex 조언 받고»
Mockup: `.planning/mockups/2026-10-15-facturacion-cuit-cert-sucursal/mockup.png`

## Hoy
- Config › Facturación: Docs · CertificadoCard (UNO por tienda: `GET /afip/cert` → `estado(storeId)` =
  primer emisor por PV) · Padrón · IssuerConfig (lista PV + formulario + logo) · switch · % · EmisoresCard
  (grilla sucursal × emisor).
- Acciones de certificado (`cert/csr` GET/POST, `upload`, `activar`, `revertir`) YA aceptan `issuerId`.
- `GET /afip/issuers/certificados` ya da un resumen de certificado por emisor.
- `activarCertSlug` mueve `cert_slug` sólo del emisor indicado (no de los otros PV del mismo CUIT).
- Branch ↔ emisor: `GET/PUT /afip/sucursales/:id/emisores` {issuerIds, predeterminadoId}.
- Prod: 6 tiendas con emisor, todas 1 CUIT (store 19: 2 PV, 1 slug).

## Plan
### Servidor
S1. `GET /afip/cert?issuerId=` → `estado(storeId, issuerId?)` (emisorDe ya lo soporta). Sin issuerId = como hoy.
S2. `activarCertSlug` / `revertirCertSlug`: además del emisor indicado, mover a los OTROS emisores de la
    misma tienda y mismo CUIT **que usaban el mismo slug anterior** (un certificado = un CUIT). Misma transacción.
S3. Nada de DB.

### Front (Config › Facturación) — compacto
F1. `EmisoresTiendaCard` reemplaza a CertificadoCard (tarjeta única) + IssuerConfig + EmisoresCard en esta página:
    - una sección por CUIT: 1 línea de datos (CUIT · razón social · IVA · «Editar datos»), 1 línea de
      certificado (CertificadoCard con `issuerId` = primer PV del CUIT y `compacto`: chip de estado + botón;
      el detalle/guía se despliega sólo si hay que actuar o al tocar), tabla de PV (PV · «Lo usan» sólo
      lectura · Editar/Quitar) y «+ PV».
    - «+ Agregar CUIT» y «Editar datos/PV» = diálogo con el formulario actual de IssuerConfig.
    - slugDestino con carpeta compartida: `ventago_st{store}` para el CUIT del 1er emisor (como hoy);
      para otro CUIT `ventago_st{store}_{cuit}` (si no, dos CUIT pisarían la misma carpeta).
    - Logo del comprobante: queda como fila chica aparte.
F2. IssuerConfig sigue igual para el detalle de tienda del superadmin (no se toca).

### Front (Sucursales)
F3. Editar sucursal: sección «Factura electrónica» = lista de emisores (CUIT · PV) con ☑ y ★, reglas de
    `emisores-matriz.ts`; los de CUIT sin certificado vigente, deshabilitados (salvo si ya estaban marcados).
    Guarda con `PUT /afip/sucursales/:id/emisores` al guardar la sucursal.
F4. Lista de sucursales: columna «Factura con» (★ PV o «Cualquiera»).
F5. La grilla sale de Config › Facturación (sigue en el detalle de tienda del superadmin).

## Preguntas para CODEX
1. S2: ¿mover también los otros PV del mismo CUIT es correcto/seguro? ¿riesgos?
2. ¿Deshabilitar en la sucursal los emisores sin certificado puede romper algo (fallback del servidor)?
3. slugDestino por CUIT: ¿problemas?
4. ¿Algo que se pierda al sacar la grilla y la tarjeta única de Config?
