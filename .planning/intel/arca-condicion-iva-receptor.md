# ARCA — Condición Frente al IVA del Receptor (RG 5616)

출처: Manual para el Desarrollador ARCA COMPG **v4.0**, ANEXO «Condición Frente al IVA del receptor»
https://www.afip.gob.ar/ws/documentacion/manuales/manual-desarrollador-ARCA-COMPG-v4-0.pdf
추출: 2026-09-08 (pdftotext -layout)

★ 2차 자료를 믿지 말 것 — 검색으로 나온 요약본들은 시행일을 2026-09-01 로 적고 있으나
  ARCA 가 보낸 실제 통지서(2026-09-07)는 **2026-12-01** 이다. 우리 코드가 맞다.
★ 런타임 권위 출처는 WS 메서드 `FEParamGetCondicionIvaReceptor` 다 (우리 SOAP 클라이언트에 아직 없음).

```
Condición Frente al IVA del receptor
                         CONDICIÓN FRENTE AL IVA

                                                  COMPROBANTE
                                                             49 – Comprob.
                                                             de Compra de
                                                 CLASE       Bienes Usados

Código                Descripción          A/M    B      C       49

    1       IVA Responsable Inscripto       X            X

    4       IVA Sujeto Exento                     X      X

    5       Consumidor Final                      X      X        X

    6       Responsable Monotributo         X            X

    7       Sujeto No Categorizado                X      X

    8       Proveedor del Exterior                X      X

    9       Cliente del Exterior                  X      X

   10       IVA Liberado – Ley N° 19.640          X      X

   13       Monotributista Social           X            X

   15       IVA No Alcanzado                      X      X

            Monotributo Trabajador
   16       Independiente Promovido         X            X
```
