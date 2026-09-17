# Phase 89 — 상품 이미지 파일명 모지바케 진단

**실행:** 2026-09-16 · 대상: 운영 5434(PostgreSQL) + 운영 MinIO(`apiminio.coolsistema.com`, 읽기 전용)

## 판정

**판정: ⓑ — MinIO 에 "깨진 이름 그대로" 저장돼 있다. 원인은 조립/전송(업로드) 경로이고, DB 는 정확하다.**

`products.image_url` 이 비ASCII(모지바케)인 **35건 전부**가 `raw_hit` — 즉 DB 에 적힌
그 깨진 문자열이 **MinIO 객체 키 그 자체와 정확히 일치**한다. `fix_hit`(DB 문자열만 깨짐)과
`missing`(객체 자체 없음)은 **0건**이다. 대조군(`ascii_ok`) 79건도 실제로 「존재」로 확인됐다
— 버킷 연결은 정상이다.

근거(명령 출력 원문 — 운영 컨테이너(`api_ventago`, 운영과 동일 자격증명) 안에서 실행):
```
총 114건 / ascii_ok 79 / raw_hit 35 / fix_hit 0 / brk_hit 0 / missing 0
판정: ⓑ — 업로드 시 깨진 이름 그대로 저장됐다(raw_hit 다수)

--- ascii_ok 예시 (최대 3건) ---
  id=6 raw="remera morley.png" fix="remera morley.png" brk="remera morley.png" hit={"size":34450,"etag":"bc4498a9761209fa3db3864b6b0e1ebf"}
  id=7 raw="remera morley.png" fix="remera morley.png" brk="remera morley.png" hit={"size":34450,"etag":"bc4498a9761209fa3db3864b6b0e1ebf"}
  id=8 raw="remera morley.png" fix="remera morley.png" brk="remera morley.png" hit={"size":34450,"etag":"bc4498a9761209fa3db3864b6b0e1ebf"}
--- raw_hit 예시 (최대 3건) ---
  id=313 raw="RiÃ±onera 113-1.jpg" fix="Riñonera 113-1.jpg" brk="RiÃÂ±onera 113-1.jpg" hit={"size":447065,"etag":"0f69c5cadc9d2e778b81517878c1fa1e"}
  id=314 raw="RiÃ±onera 113-1.jpg" fix="Riñonera 113-1.jpg" brk="RiÃÂ±onera 113-1.jpg" hit={"size":447065,"etag":"0f69c5cadc9d2e778b81517878c1fa1e"}
  id=315 raw="RiÃ±onera 113-1.jpg" fix="Riñonera 113-1.jpg" brk="RiÃÂ±onera 113-1.jpg" hit={"size":447065,"etag":"0f69c5cadc9d2e778b81517878c1fa1e"}
--- fix_hit 예시 (최대 3건) ---
  (없음)
--- brk_hit 예시 (최대 3건) ---
  (없음)
--- missing 예시 (최대 3건) ---
  (없음)
```

## 무엇을 확인했고 무엇을 확인하지 않았는가

| 경로 | 상태 | 근거 |
|---|---|---|
| 1 `products.service.ts:339-361` `imageName` | 확인 — 후보 경로로 유지 | `grep -rn "imageName" api-ventago/src/app \| grep -v spec` → `products.service.ts:149,340` + `create-products.dto.ts:132` 세 곳뿐. `imageName` 은 **클라이언트가 요청 바디로 넘기는 값**이고, 있으면 그 값을 그대로 최종 파일명으로 쓴다(`finalImageName = imageName`). 이 값 또는 `imageFile.originalname` 이 이미 모지바케 상태로 컨트롤러에 도달했다면, 그 뒤 `uploadFile()` 은 검증 없이 그대로 MinIO 키로 쓴다 — raw_hit(원인이 저장 이전 단계) 관측과 일치 |
| 2 Multer/Busboy 기본 charset | 확인 — 배제되지 않음(가장 유력) | `grep -rna "defParamCharset\|defCharset\|busboy" api-ventago/src` → **0건**. 즉 이 저장소 어디에도 multipart charset 을 명시적으로 지정한 곳이 없다 — Multer(Busboy) 기본 디코딩을 그대로 쓴다는 뜻이다. 브라우저가 `Content-Disposition: filename="Riñonera 113-1.jpg"` 를 UTF-8 바이트로 실어 보내고 서버가 이를 latin1 로 잘못 해석하면 정확히 `RiÃ±onera` 형태(UTF-8 바이트 0xC3 0xB1 을 latin1 두 글자 Ã· ± 로 잘못 읽은 것)가 만들어진다 — 관측값과 정확히 일치한다 |
| 3 `minio.controller.ts` sanitize (`[^\w.-]→_`) | 배제됨 | 이 경로를 탔다면 `ñ` 는 `_` 로 치환됐어야 하는데, 관측된 raw 값(`RiÃ±onera 113-1.jpg`)에는 밑줄 치환 흔적이 없다. 즉 이 sanitize 함수를 거치지 않은 별도 업로드 경로(경로 1, 상품 모듈 전용)를 통과했다 |
| 4 프론트 URL 조립(9곳, `encodeURIComponent` 없음) | 확인 — 원인 아님 | raw_hit 35건 전부가 MinIO 실제 키와 **일치**하므로, 이 조립 단계는 이미 깨진 값을 그대로 옮겼을 뿐 **새로 깨뜨리지 않았다**. 404 의 직접 원인(브라우저 자동 percent-encode 결과가 실제 저장 키와 달라짐)이지, 모지바케 자체의 생성 원인은 아니다 |
| 5 `MinioController.getImage`(서빙) | 확인 — 원인 아님, 404 가 발생하는 자리 | `getObjectStream()` 은 받은 파일명을 그대로 `client.getObject()` 에 넘긴다. 디코딩을 하지 않으므로 브라우저가 만든 URL 인코딩 문자열과 MinIO 실제 키가 다르면 여기서 404 로 떨어진다 — 이번 진단의 재현 대상은 아니고 증상이 관측되는 지점일 뿐이다 |

## 고치지 않은 이유와 다음에 해야 할 일

- 이 plan 은 **고치지 않는다.** 판정이 ⓑ(업로드 시 깨진 이름으로 저장됨)이므로 필요한
  조치는 **두 갈래**다:
  1. **재발 방지(코드)**: 상품 이미지 업로드 경로(경로 1, `products.service.ts` 의
     `create()`/`update()` — `imageName`/`imageFile.originalname` 처리부)에 비ASCII
     파일명을 안전하게 다루는 로직을 추가한다(예: Busboy 옵션으로 `defParamCharset: 'utf8'`
     지정, 또는 업로드 직전 서버측에서 `latin1→utf8` 보정 후 저장, 또는 애초에 관리자
     sanitize(`minio.controller.ts`)와 같은 규칙을 상품 업로드 경로에도 통일 적용).
  2. **기존 35건 데이터 정정**: MinIO 에 이미 깨진 이름으로 저장된 객체를 올바른
     이름으로 **복사(copyObject)** 하고, `products.image_url` 을 그 정확히 35개 행에
     대해서만 갱신한다. (원본 객체를 지우는 것은 이 조치의 필수 요소가 아니다 —
     안전을 위해 남겨 두고 별도 정리 단계에서 처리할 수 있다.)
- 그 조치의 영향 범위: **정확히 35행**(`products.image_url` 비ASCII 전부), MinIO 객체는
  전부 실재하므로 삭제·복구 위험 없이 **읽기+복사**만으로 해결 가능하다.
- **일괄 치환 금지 근거**: 짧은 토큰 일괄 치환으로 두 번 사고가 난 전례가 있다.
  치환한다면 대상은 `products.image_url` 의 **정확히 이 35행**이고, 각 행에 대해
  `latin1→utf8` 변환 후 키(`fix` 후보)가 MinIO 에 **새로 존재하도록 복사**한 뒤 그 복사가
  성공했음을 개별로 `statObject` 확인한 다음에만 DB 를 갱신한다 — 지금 이 35건은
  `fix` 후보가 MinIO 에 **없다**(raw 만 존재), 따라서 "DB 문자열만 바꾸는" 정정은
  **통하지 않는다** — 반드시 MinIO 객체 복사가 선행돼야 한다는 것이 이번 진단의
  실질적 결론이다.
- 후속 phase 후보로 ROADMAP 에 올릴 것인가: **예** — 이 phase(89)의 목표인 공개 상품
  페이지가 사진을 보여줘야 하는데, 상품 절반이 사진 404 상태이기 때문이다. 다만 이
  plan 의 범위가 아니므로 별도 후속 plan(가칭 "이미지 모지바케 정정 — 복사+DB 갱신,
  35건, 각 건 사후 검증 포함")으로 등록한다. 89-06 은 "사진 없어도 안 깨지는" UI 방어만
  다루므로 이 정정과는 별개다.

## 부수 발견 — 진단 도구 자체의 버그 (운영 서비스와 무관)

`api-ventago/scripts/diagnose-image-names.js` 최초 버전은 `port` 를
`Number(process.env.MINIO_PORT)` 로 변환해 사용했는데, 운영 컨테이너 안에서 직접
재현한 결과 minio@8.0.7 클라이언트가 **숫자 443** 을 받으면 서명 계산에 쓰는 Host
문자열이 실제 요청과 달라져 `SignatureDoesNotMatch` 를 낸다(같은 자격증명·같은 값,
타입만 다름). **문자열 `'443'`** 을 그대로 넘기면 정상 동작한다(실제
`minio.service.ts` 도 `ConfigService.get()` 원본을 그대로 넘긴다 — 같은 형태로
수정). 이 문제는 스크립트 자체의 버그였고, 운영 애플리케이션(`/api/minio/:filename`)은
이 결함과 무관하게 계속 정상 작동 중이었다(`docker logs` 로 200 확인). 스크립트는
수정 후 커밋했다 — DB·MinIO 에 대한 쓰기는 이 수정에도 포함되지 않았다(읽기 전용
유지).

## 실행 확인 — 이 plan 은 아무것도 고치지 않았다

- `products.image_url` 에 대한 UPDATE **0건 실행**.
- MinIO 에 대한 `putObject`/`removeObject`/`copyObject` **0건 실행**.
- 이번 세션에서 실행한 것은 전부 `SELECT`(운영 5434, 읽기 전용)와 `statObject`/`getObject`
  (MinIO, 읽기 전용) 뿐이다.
