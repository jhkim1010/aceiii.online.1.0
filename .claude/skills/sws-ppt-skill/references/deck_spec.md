# deck.json 스키마 — build_ppt.py 입력 명세

`scripts/build_ppt.py deck.json salida.pptx` 로 렌더링. 모든 스타일(폰트/크기/위치/자동맞춤)은
스크립트가 담당하므로, 여기서는 **내용만** 채운다. 텍스트 내 줄바꿈은 `\n`.

## 최상위 구조
```json
{
  "meta": { "font": "Arial", "accent": "#142A5A", "text": "#111111" },
  "slides": [ { "type": "...", ... }, ... ]
}
```
`meta` 는 모두 선택. 기본값(Arial / 딥네이비 / 먹색, 흰 배경)이면 생략 가능.

## 슬라이드 타입

### cover — 표지
`{ "type":"cover", "title":"Culto Dominical", "subtitle":"Domingo 20 de julio de 2026", "guiador":"P. Cristian" }`

### section — 예배 순서 구분(큰 순서명 + 세부 + 섬김이)
`{ "type":"section", "orden":"Ofrenda", "detalle":"", "servidor":"" }`
- `orden`: 순서명(대형). 예: "Oración silenciosa", "Ofrenda", "Anuncio".
- `detalle`: 부가정보(선택). 예: "(de pie) N° 447", "San Mateo 16:13-28".
- `servidor`: 섬기는 사람(선택). 예: "M. Caleb", "m. Marcos".
  이름이 붙은 순서는 반드시 `servidor` 를 채운다.

### hymn_title — 찬송 제목 표지
`{ "type":"hymn_title", "numero":"447", "titulo":"제목" }`

### hymn — 찬송 가사 (핵심 규칙 아래 참고)
`{ "type":"hymn", "heading":"N° 447 · Estrofa 1", "body":"1절 가사...", "coro":"후렴..." }`
- `heading`: 라벨(예: "N° 447 · Estrofa 1", "N° 447 · Coro").
- `body`: 그 슬라이드의 주 가사.
- `coro`: (선택) 아래쪽에 금색 구분선과 함께 후렴 표시.

**후렴 규칙**
- 후렴이 **짧으면**: 절마다 1슬라이드 = `body`(그 절) + `coro`(후렴) 함께.
- 후렴이 **길면**: 절마다 2슬라이드 = ①`body`=그 절(coro 생략) ②`body`=후렴(heading="N°… · Coro").
- 후렴이 없으면: 절마다 1슬라이드(`body`만).

### credo — 사도신경 (references/credo.md 텍스트 그대로, 3장 고정)
`{ "type":"credo", "pagina":1, "total":3, "texto":"..." }`

### passage — 성경 봉독 (Leer pasaje), 페이지당 2~4절
```json
{ "type":"passage", "referencia":"San Mateo 16:13-14",
  "versiculos":[ {"n":13,"t":"..."}, {"n":14,"t":"..."} ] }
```

### message_title — 메시지 제목 + 요절 + 설교자
`{ "type":"message_title", "kicker":"Mensaje", "titulo":"제목", "versiculo_clave":"San Mateo 16:16", "texto_clave":"요절 본문", "predicador":"m. Marcos" }`

### message_part — 메시지 파트 구분
`{ "type":"message_part", "parte":"I. El título de la parte", "subtitulo":"부제(선택)" }`

### scripture — 메시지 중 '본문 읽기' 절 (RV1960 전문). passage 와 동일 필드.
```json
{ "type":"scripture", "referencia":"San Mateo 16:24-26",
  "versiculos":[ {"n":24,"t":"..."}, ... ] }
```

### illustration — 삽화 (도형 모티프 또는 이미지)
`{ "type":"illustration", "motivo":"cross", "caption":"짧은 문구(선택)" }`
- `motivo`: cross/cruz, book/biblia/libro, heart/corazon, light/luz/sol, star/estrella, dove/paloma/espiritu, fish/pez. (없으면 원형 배지)
- 또는 `"image":"/경로/그림.png"` 로 실제 이미지 삽입(있을 때만).

### key_verse_repeat — 메시지 끝에서 제목+요절 반복 (message_title 과 동일 필드)
`{ "type":"key_verse_repeat", "kicker":"", "titulo":"메시지 제목", "versiculo_clave":"...", "texto_clave":"..." }`

### lords_prayer — 주기도문 (references/padrenuestro.md 텍스트 그대로, Anuncio 뒤 3장)
`{ "type":"lords_prayer", "pagina":1, "total":3, "texto":"..." }`

### big_text — 임의의 큰 텍스트(범용, 필요 시)
`{ "type":"big_text", "heading":"", "texto":"..." }`
