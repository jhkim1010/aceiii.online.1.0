# ACE → VentaGO Excel 변환 가이드 / Guía de conversión ACE → VentaGO

오프라인 ACE 레거시 DB 를 읽어 VentaGO 의 "Importar códigos" 화면이 받는
Excel(.xlsx) 형식으로 변환합니다.
Convierte la base de datos legacy de ACE al formato Excel (.xlsx) que acepta
la pantalla "Importar códigos" de VentaGO.

---

## 1. 설치 / Instalación

오프라인 PC 에 Python 3.8+ 이 필요합니다 / Requiere Python 3.8+ en la PC offline.

```bash
cd tools
pip install -r requirements.txt
```

설치 패키지 / Paquetes: `psycopg2-binary`, `openpyxl`

---

## 2. 실행 / Ejecución

### 인자로 접속 / Conexión por argumentos

```bash
python ace_to_ventago_excel.py \
    --host localhost \
    --port 5432 \
    --db ace_db \
    --user postgres \
    --password MIPASSWORD \
    --output export_ventago.xlsx
```

### 환경변수로 접속 / Conexión por variables de entorno

```bash
export ACE_DB_HOST=localhost
export ACE_DB_PORT=5432
export ACE_DB_NAME=ace_db
export ACE_DB_USER=postgres
export ACE_DB_PASSWORD=MIPASSWORD

python ace_to_ventago_excel.py --output export_ventago.xlsx
```

비밀번호 미지정 시 / Si no se indica contraseña:
인터랙티브 터미널이면 안전하게 프롬프트로 입력받습니다.
En terminal interactiva, la pide de forma segura por prompt.

---

## 3. 먼저 스키마 확인 (권장) / Verificar el esquema primero (recomendado)

ACE DB 의 실제 컬럼명은 PC 마다 다를 수 있습니다. 변환 전 `--inspect` 로
컬럼 매핑이 올바른지 먼저 확인하세요.
Los nombres de columna reales pueden variar. Antes de convertir, verifique el
mapeo con `--inspect`.

```bash
python ace_to_ventago_excel.py --db ace_db --user postgres --inspect
```

출력 예 / Salida de ejemplo:

```
[todocodigos] 실제 컬럼: ['tcodigo', 'tdesc', 'tpre1', ...]
  OK sku            → tcodigo
  OK name           → tdesc
  OK price1         → tpre1
  !! fk_temporada   → (미탐지)
```

`!!` 로 표시된 미탐지 필드가 있으면, 스크립트 상단의 후보 목록
(`PARENT_FIELD_CANDIDATES`, `VARIANT_FIELD_CANDIDATES`, `REFERENCE_TABLES`)에
실제 컬럼명을 추가하면 됩니다.
Si hay campos no detectados (`!!`), agregue el nombre real de la columna a las
listas de candidatos en la parte superior del script.

---

## 4. 옵션 / Opciones

| 옵션 / Opción | 설명 / Descripción |
|---|---|
| `--output PATH` | 출력 파일 경로 (기본 `export_ventago.xlsx`) |
| `--schema NAME` | 테이블 스키마 (기본 `public`) |
| `--include-deleted` | `borrado=true` 행도 포함 (기본: 제외) |
| `--enrich-description` | temporada/origen/empresa 를 description 에 병합 (기본: 드롭) |
| `--inspect` | 컬럼 매핑만 출력 후 종료 (디버깅) |
| `--debug` | 상세 로그 출력 |

---

## 5. 생성되는 Excel 형식 / Formato del Excel generado

VentaGO `GET /code-import/template` 와 **완전히 동일** / **Idéntico** al template.

| 시트 / Hoja | 컬럼 / Columnas |
|---|---|
| **Colors** | `name`, `hex` |
| **CodigoMadres** | `sku`, `name`, `price`, `priceOrig`, `description`, `categoryName` |
| **CodigoHijitos** | `parentSku`, `sku`, `name`, `colorName`, `size`, `price`, `priceOrig`, `stock`, `price1`~`price5` |

### 매핑 / Mapeo

| VentaGO | ← ACE |
|---|---|
| Colors.name | `color.descripcioncolor` (+ 변형 descripcion 에서 파싱된 색상) |
| CodigoMadres.sku | `todocodigos.tcodigo` |
| CodigoMadres.name | `todocodigos.tdesc` |
| CodigoMadres.price | `todocodigos.tpre1` |
| CodigoMadres.categoryName | `tipos.tpdesc` (FK) |
| CodigoHijitos.parentSku | `codigos.codigoproducto` |
| CodigoHijitos.sku | `codigos.codigo` |
| CodigoHijitos.name | `codigos.descripcion` |
| CodigoHijitos.colorName | `color` FK lookup → 없으면 descripcion `(ROJ)` 파싱 |
| CodigoHijitos.size | `str_talle` → 없으면 SKU 끝자리 파싱 |
| CodigoHijitos.price1~5 | `codigos.pre1`~`pre5` |
| CodigoHijitos.stock | `codigos.stock`/`cantidad`/`existencia` (있으면) |

> ⚠ **store_id 는 지정하지 않습니다.** VentaGO import 시 로그인한 매장으로 자동 할당됩니다.
> No se asigna `store_id`; VentaGO lo asigna automáticamente al importar.

> ⚠ VentaGO 템플릿에는 **season/origin/supplier 컬럼이 없습니다.**
> 기본적으로 드롭되며, `--enrich-description` 으로 description 에 병합할 수 있습니다.
> El template no tiene columnas season/origin/supplier; se descartan salvo que
> use `--enrich-description`.

---

## 6. 결과 리포트 / Reporte de resultados

실행 후 콘솔에 요약이 출력됩니다 / Al terminar se imprime un resumen:

```
색상(Colors)       : N 건
부모(CodigoMadres) : N 건 export, N 건 스킵
자식(CodigoHijitos): N 건 export, N 건 스킵
⚠ 색상 파싱 실패   : N 건 (수동 확인 필요)
⚠ 사이즈 파싱 실패 : N 건
⚠ 부모 없는 자식   : N 건
```

색상/사이즈 파싱 실패 SKU 는 샘플이 출력되므로, 생성된 Excel 에서 해당 행을
수동 보정 후 업로드하세요.
Los SKU con fallo de parseo se muestran como muestra; corrija manualmente esas
filas en el Excel antes de subir.

---

## 7. 업로드 / Subir a VentaGO

1. VentaGO 로그인 (대상 매장) / Inicie sesión en VentaGO (tienda destino)
2. 상품 → "Importar códigos" / Productos → "Importar códigos"
3. 생성된 `export_ventago.xlsx` 업로드 / Suba el `export_ventago.xlsx`
4. 충돌 정책(skip/update/link) 선택 후 실행 / Elija política y ejecute
