---
name: sws-ppt-skill
description: 주일 예배(Sunday Worship Service) 순서 PPT를 자동 제작하는 스킬. 예배 순서표와 설교 메시지 Word 파일을 받아, 멀리서도 잘 보이는 고대비(흰 배경·검정 글씨) 16:9 PowerPoint를 생성한다. 순서 구분 슬라이드, Himno 가사(PDF에서 추출·후렴 규칙), Credo Apostólico 3페이지, 성경 봉독(페이지당 2~4절), 메시지 파트+RV1960 성경 절 전문, 삽화, 요절 반복, Padre Nuestro 3페이지를 포함한다. "예배 PPT", "주일 예배 슬라이드", "culto dominical", "Himnario", "예배 순서 PPT" 요청 시 사용. 매주 금요일 밤 예약 작업으로도 실행됨.
---

# 주일 예배 PPT 제작 (sws-ppt-skill)

너는 일러스트와 PPT를 잘 다루는 전문가다. 아래 절차대로 **정확하고 일관되게** 주일 예배 슬라이드를 만든다.

## 0. 반드시 먼저 — 두 가지 입력 요청 + 지난 로그 확인
작업 시작 전에 **항상**:
1. **예배 순서표**와 각 순서의 **섬기는 사람 이름** (텍스트로 붙여넣기).
2. **설교 메시지 전문 Word 파일** (.docx).
   - 두 번째 찬송(메시지 후) 및 첫 찬송의 **Himno PDF 파일**도 함께 요청한다("가사 PDF").
   - PDF가 없으면 해당 찬송 가사 슬라이드는 만들 수 없으니, 번호만이라도/PDF를 달라고 명확히 요청.

그리고 **직전 실행 로그**(`logs/last-run.md`)가 있으면 먼저 읽어, 지난주 발견한 문제·개선점을 이번에 반영한다. (사용자 원칙: "항상 마지막 로그파일을 확인하고 수정 작업을 한다.")

무거운/불필요한 작업은 피한다. 이 스킬은 DB를 쓰지 않으므로 커넥션 풀 걱정은 없지만, 원칙대로 낭비 없이 최소한의 웹 호출(성경 절)만 한다.

## 1. 준비
```bash
pip install python-pptx --break-system-packages -q   # 없으면 설치
```
스킬 폴더의 `scripts/build_ppt.py` 가 렌더러다. 너는 **콘텐츠(deck.json)** 만 만들고, 스타일/폰트/자동맞춤은 스크립트가 담당한다. 스키마는 `references/deck_spec.md` 참고.

작업 디렉터리를 하나 만들고(예: `/tmp/culto_YYYYMMDD/`) 거기서 진행한다. Himno/메시지 파일은 device_stage_files 로 스테이징해서 읽는다.

## 2. deck.json 조립 규칙 (순서표를 그대로 슬라이드로)
순서표의 각 항목을 위에서부터 슬라이드로 변환한다. **모든 텍스트는 크게, 고대비.** 기본 표지(cover)로 시작한다.

각 예배 순서 항목마다 먼저 **`section` 구분 슬라이드**(큰 순서명 + 세부 + 섬기는 사람)를 넣고, 내용이 있는 항목은 그 뒤에 내용 슬라이드를 잇는다.

| 순서 유형 | 슬라이드 구성 |
|---|---|
| Guiador | `cover` 의 `guiador` 로 표기(별도 section 불필요) |
| Oración silenciosa / Ofrenda 등 단순 순서 | `section` 1장 (섬김이 있으면 `servidor`) |
| Oración representativa: 이름 | `section` (servidor=이름) |
| **Himno / Cántico (번호+PDF)** | `section` → `hymn_title` → `hymn`(가사) 여러 장. **후렴 규칙 아래 §3** |
| **Credo (Apostólico)** | `section` → `credo` **3장 고정** (`references/credo.md` 텍스트 그대로) |
| **Leer pasaje: 책 장:절** | `section`(detalle=참조) → `passage` 여러 장. **RV1960, 페이지당 2~4절, §4** |
| Cancion Especial: 이름 | `section` (servidor=이름). 특별찬양은 보통 가사 슬라이드 없음(요청 시 추가) |
| **Mensaje: 이름** | `message_title` → (`message_part`/`scripture`/`illustration` 반복) → `key_verse_repeat`. **§5** |
| **Anuncio: 이름** | `section`(servidor=이름) → 그 **뒤에 `lords_prayer` 3장 고정** (`references/padrenuestro.md`) |

표지 부제는 스페인어 날짜: "Domingo D de mes de AAAA" (예: "Domingo 20 de julio de 2026").

## 3. Himno (찬송) — PDF에서 가사만 추출
1. 사용자가 준 PDF를 읽는다(Read 로 PDF 페이지 이미지/텍스트 확인). **Bautista Himnario** 기준으로 **가사만** 추출(악보·성부·저작권 표기 제외).
2. 절(estrofa)과 후렴(coro)을 구분한다.
3. **후렴 길이 규칙:**
   - **후렴이 짧으면** → 절마다 1슬라이드: `hymn` 의 `body`=그 절, `coro`=후렴 (함께 표시).
   - **후렴이 길면** → 절마다 2슬라이드: ① `body`=그 절(coro 생략) ② `body`=후렴(heading="N°… · Coro").
   - **후렴이 없으면** → 절마다 1슬라이드(`body`만).
4. 절이 매우 길면 한 절을 2장으로 나눠도 된다(가독성 우선). `hymn_title` 로 번호/제목 표지 먼저.

## 4. 성경 봉독 (Leer pasaje) — RV1960
- `references/bible_rv1960.md` 의 방법으로 **RV1960** 본문을 WebFetch(BibleGateway)로 가져온다.
- **페이지당 2절 또는 4절**: 절이 길면 2절/페이지, 짧으면 4절/페이지.
- `passage` 슬라이드의 `versiculos` 배열에 `{ "n": 번호, "t": "본문" }` 로. 각주기호 제거.
- 절 개수가 참조 범위와 맞는지 검증(예: 16:13-28 = 16개 절).

## 5. 메시지 (Mensaje)
1. Word(.docx)를 읽어(예: python-docx 또는 mammoth) 다음을 파악: **메시지 제목**, **요절(versículo clave)**, **파트 구분**, 본문에서 **"읽자/leamos …" 로 지시하는 성경 절**.
   ```bash
   pip install python-docx --break-system-packages -q
   python3 -c "import docx,sys; print('\n'.join(p.text for p in docx.Document(sys.argv[1]).paragraphs))" mensaje.docx
   ```
2. 슬라이드 순서:
   - `message_title` (kicker="Mensaje", titulo, versiculo_clave, texto_clave, predicador=이름)
   - 각 파트마다 `message_part` (parte="I. …", 필요시 subtitulo)
   - 파트 안에서 **"본문 몇 절을 읽자"** 는 지점마다 반드시 `scripture` 슬라이드 = **RV1960 해당 절 전문**(한 페이지 가득, 2~4절/페이지, §4 동일).
     - **전문(full) 원칙, 축약 금지:** 메시지가 인용/언급하는 모든 성경 구절은 절 전체 내용을 한 자도 빼지 말고 넣는다. 요약·생략·'...' 축약 금지. 원고에 따옴표로 인용된 절은 그 인용문과 대조해 동일 범위를 전문으로 싣고, 참조만 한 절(교차구절)도 해당 절 전체를 RV1960으로 싣는다. 원고 인용문과 RV1960 표기가 미세하게 다르면(강세·대소문자) RV1960 기준, 범위·문장은 원고가 읽는 그대로 전부 포함.
   - 중간중간 **성경 삽화** `illustration` 삽입(주의 환기). `caption` 은 짧은 스페인어 한 줄. 과하지 않게 파트당 0~1장.
     - **기본 스타일 = 발로통풍 미니멀 선화**(Annie Vallotton 양식 참고한 오리지널; 흰 배경·검정 한 붓 선·여백 많음·표정 없음). 장면: `transfiguracion`(변형·monte·gloria), `dos_figuras`(moisés·elías·comunión), `nube_voz`(구름의 음성·voz). 본문 장면에 맞게 고른다.
     - **대체 스타일 = 고전 판화(engraving)**: 같은 장면의 `transfiguracion_grabado` / `dos_figuras_grabado` / `nube_voz_grabado`. 사용자가 판화를 원하면 이걸 쓴다.
     - 보조 아이콘(선형): cross(cruz), sun(sol), dove(paloma), book(biblia), empty_tomb(resurrección), crown(rey), flame(fuego), heart(amor), star.
     - 모든 삽화 PNG는 `assets/illustrations/<motivo>.png`. 새 장면이 필요하면 `assets/make_vallotton.py`(선화, 기본) 또는 `assets/make_engravings_*.py`(판화)에 추가해 재생성. **실제 화가 작품을 복제하지 말고** 양식만 참고한 오리지널로. 유아틱한 플랫 아이콘풍은 지양.
   - 메시지 끝: `key_verse_repeat` (titulo=메시지 제목, versiculo_clave/texto_clave=요절) — 제목과 요절을 다시 읽도록.
3. 요절 본문도 RV1960 로 정확히.

## 6. Credo / Padre Nuestro (고정 텍스트)
- `references/credo.md` → `credo` 3장. **수정·의역 금지, 그대로.**
- `references/padrenuestro.md` → `lords_prayer` 3장. 사용자가 준 음절 하이픈(노래용) **그대로 유지**. Anuncio **뒤**, 예배 맨 마지막.

## 7. 생성 · 검증 · 전달
```bash
python3 <스킬>/scripts/build_ppt.py deck.json /tmp/culto_YYYYMMDD/Culto_YYYY-MM-DD.pptx
soffice --headless --convert-to pdf --outdir /tmp/culto_YYYYMMDD /tmp/culto_YYYYMMDD/Culto_YYYY-MM-DD.pptx
```
- PDF를 몇 장 열어(Read) **글자 잘림/겹침/오탈자**를 확인한다. 문제 있으면 deck.json 을 고쳐 재생성.
- 특히: **메시지가 인용/언급한 모든 절이 전문(축약 없이)으로 들어갔는지 원고와 대조**, 성경 절 개수, 후렴 규칙 적용, Credo/주기도문 3장, 이름 표기, 제목/요절 반복, 삽화가 선형(line-art)으로 삽입됐는지 확인.
- **전달**: `SendUserFile` 로 .pptx 를 보낸다. 사용자가 원하면 device_commit_files 로 Mac에도 저장.
- **로그 남기기**: `logs/last-run.md` 에 이번 실행 요약(날짜, 순서, 사용한 찬송 번호, 발견/수정한 이슈, 개선 아이디어)을 저장 → 다음 주에 참고.

## 디자인 규격 (고정)
- 16:9, **흰 배경 + 검정 글씨**(고대비, 원거리 가독). 강조는 딥네이비, 요절/후렴 포인트는 금색.
- 모든 슬라이드 글자는 `build_ppt.py` 가 박스에 맞춰 **최대한 크게 자동 조정**한다. 텍스트가 넘치면 절/문장을 더 잘게 나눠 슬라이드를 추가(작게 줄이지 말 것).
- 이름·순서명은 뒷자리에서도 보이도록 충분히 크게.

## 산출 파일 이름
`Culto_YYYY-MM-DD.pptx` (해당 주일 날짜).
