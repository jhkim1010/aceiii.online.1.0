# RV1960 (Reina-Valera 1960) 성경 본문 확보 방법

메시지의 "본문 읽기" 절과 `Leer pasaje` 순서의 절 내용은 **반드시 RV1960**에서 가져온다.

## 1순위 — BibleGateway (검증됨, 키 불필요)
WebFetch 로 아래 URL 패턴을 호출한다. 참조를 URL 인코딩할 것.

```
https://www.biblegateway.com/passage/?search=<REFERENCIA>&version=RVR1960
```

예) `Mateo 16:13-15` →
```
https://www.biblegateway.com/passage/?search=Mateo+16%3A13-15&version=RVR1960
```

WebFetch prompt 예시:
> "Return the exact verse text for each verse with its verse number, one per line, in RVR1960. Only the verse text, no footnotes or cross-references."

- 책 이름은 스페인어로: San Mateo→`Mateo`, San Juan→`Juan`, Génesis, Éxodo, Salmos, Romanos, etc. ("San" 은 빼도 검색됨.)
- 긴 구간은 한 번에 가져와도 되지만, **슬라이드 분할은 절 단위**로 한다(아래 규칙).

## 2순위 — 폴백
BibleGateway 가 실패하면:
- WebSearch 로 "`<referencia>` RVR1960 texto" 검색 후 신뢰 가능한 스페인어 성경 사이트(biblia.com, bible.com, biblestudytools.com/rvr) 를 WebFetch.
- 그래도 안 되면 **임의로 지어내지 말고**, 사용자에게 해당 절 본문을 붙여달라고 요청한다.

## 슬라이드 분할 규칙 (원거리 가독성)
- `Leer pasaje` / `scripture`: **페이지당 2절 또는 4절.**
  - 절이 길면(평균 1절이 약 25단어↑) → **2절/페이지**
  - 절이 짧으면 → **4절/페이지**
- 각 절은 `{ "n": 13, "t": "본문..." }` 형태로 `versiculos` 배열에 넣는다.
- 절 본문에서 각주 기호(예: `[a]`)·상호참조는 제거.

## 검증
가져온 본문을 슬라이드에 넣기 전에 절 수(개수)가 참조 범위와 일치하는지 확인한다.
예: `16:13-28` → 16장 13~28절 = 16개 절이 모두 있어야 한다.
