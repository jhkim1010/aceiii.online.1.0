# 플랜 B — cool-invoice 게이트웨이 CondicionIVAReceptorId 패치
작성일: 2026-07-20 · 대상 저장소: gitlab WillAular/invoiceah (운영 배포본: /var/lib/jenkins/workspace/cool-invoice)
목적: **RG 5616 유예 종료(2026-08-31) 전에** 게이트웨이 경로도 수신자 IVA 조건을 전송하게 함.
Ventago 는 이미 `condicionIVAReceptorId` 를 body 로 보내고 있으므로 게이트웨이 2개 파일만 수정하면 됨.

## 변경 1 — `src/core/helpers/afip/lib/SoapMethods.ts`

`IParamsFECAESolicitar` 의 `FECAEDetRequest` 블록에 필드 1개 추가 (MonCotiz 다음 줄):

```ts
                    MonId: 'PES';
                    MonCotiz: number;
                    // RG 5616 수신자 IVA 조건 — 2026-09-01부터 미전송 시 거부 (오류 10242)
                    CondicionIVAReceptorId?: number;
```

## 변경 2 — `src/core/helpers/afip/afip-v2.ts`

`create()` 안의 `dataInvoice` 조립 직후(서비스 날짜 처리 블록 앞)에 추가:

```ts
      // RG 5616: 클라이언트(Ventago)가 보낸 수신자 IVA 조건 전달 — 2026-09-01부터 필수
      if (data.condicionIVAReceptorId) {
        dataInvoice.params.FeCAEReq.FeDetReq.FECAEDetRequest.CondicionIVAReceptorId =
          Number(data.condicionIVAReceptorId);
      }
```

## 미전송 클라이언트(구 시스템) 대비 — 선택 보강

구 API(apicoolsistema)는 이 필드를 안 보낼 수 있음. 기본값 폴백을 원하면 위 블록을 다음으로 대체:

```ts
      // RG 5616: 미전송 시 문서 유형으로 추정 폴백 (CUIT=RI(1), 그 외=Consumidor Final(5))
      const condIva = Number(data.condicionIVAReceptorId)
        || (Number(data.documentType) === 80 ? 1 : 5);
      dataInvoice.params.FeCAEReq.FeDetReq.FECAEDetRequest.CondicionIVAReceptorId = condIva;
```

※ 주의: CUIT=80 이라도 Monotributo(6)/Exento(4)일 수 있어 폴백은 근사치임.
   Factura A 를 쓰는 구 시스템 매장은 조건을 제대로 보내는 클라이언트 업데이트가 정도(正道).

## 검증·배포 절차 (승인 게이트 — 별도 진행)

1. gitlab 저장소에서 브랜치 생성 → 위 2개 파일 수정 → 커밋
2. homologación 인증서 slug 로 `POST /api/invoice/ar?production=false` 발급 테스트
   (오류 10242 미발생 + CAE 수신 확인)
3. 운영 배포: Jenkins cool-invoice 잡 (또는 서버에서 pull + docker 재빌드) — 사용자 승인 후
4. 배포 후 실발급 1건에서 게이트웨이 로그로 CondicionIVAReceptorId 포함 확인

## 참고

- Ventago 송신부(이미 구현됨): `api-ventago/src/app/afip/providers/rest-gateway.provider.ts`
  `toGatewayBody()` 가 `condicionIVAReceptorId: req.condIvaReceptor` 전송 중 — 게이트웨이가 현재 무시.
- 코드표: 1 RI · 4 Exento · 5 CF · 6 MT · 7 NoCat · 8 ProvExt · 9 CliExt · 10 Liberado · 13 MT Social · 15 NoAlcanzado · 16 MT Promovido
