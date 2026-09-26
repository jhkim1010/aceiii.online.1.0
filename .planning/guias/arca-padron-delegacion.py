#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ARCA Padrón 위임 절차 안내서 (PDF) 생성기.

왜 스크립트로 두는가: PDF 는 diff 가 안 된다. 내용이 바뀌면 여기를 고쳐 다시 만든다.
  /tmp/pdfvenv/bin/python .planning/guias/arca-padron-delegacion.py

★ 모든 화면 문구(스페인어)는 ARCA **공식 문서 원문**에서 가져왔다. §출처 참조.
★ 모든 「우리 상태」 숫자는 2026-09-26 운영 실측이다. 추측한 값은 없다.
"""
import os
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, KeepTogether, ListFlowable, ListItem, PageBreak,
    PageTemplate, Paragraph, Spacer, Table, TableStyle,
)

# ★ AppleGothic 을 쓰면 안 된다 — 한글은 되지만 **스페인어 악센트 글리프가 없다**.
#   2026-09-26 실측: 「Padrón」이 「Padrn」, 「inscripción」이 「inscripcin」으로 나왔다.
#   이 문서의 존재 이유가 «화면에 나오는 글자 그대로» 이므로 그건 결함이다.
#   Arial Unicode 는 한글 + 악센트 + «» 를 다 가진다(실측).
FUENTE = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'
pdfmetrics.registerFont(TTFont('KR', FUENTE))
pdfmetrics.registerFontFamily('KR', normal='KR', bold='KR', italic='KR', boldItalic='KR')

TINTA = colors.HexColor('#1a1a2e')
ORO = colors.HexColor('#f5a623')
GRIS = colors.HexColor('#5b6372')
ROJO = colors.HexColor('#b3261e')
FONDO = colors.HexColor('#f4f5f7')

ss = getSampleStyleSheet()

# ★ 굵은 글꼴이 없다 — 한글+스페인어 악센트를 모두 가진 폰트가 이 기계에 Arial Unicode 하나뿐이고
#   그 폰트에는 bold 얼굴이 없다(실측). 그래서 <b> 가 **화면상 아무 효과가 없었다**.
#   이 문서는 「이 글자를 찾으세요」가 핵심이므로 강조가 안 보이면 문서가 제 일을 못 한다.
#   → <b> 를 **색**으로 바꾼다. 굵기가 아니라 색이지만, 눈에는 확실히 띈다.
ENFASIS = '#0a58ca'
_Par = Paragraph


def Paragraph(texto, estilo, **kw):  # noqa: F811  (의도적 래핑)
    texto = texto.replace('<b>', '<font color="%s">' % ENFASIS).replace('</b>', '</font>')

    return _Par(texto, estilo, **kw)


def st(name, size, leading, **kw):
    kw.setdefault('textColor', TINTA)

    return ParagraphStyle(name, parent=ss['Normal'], fontName='KR', fontSize=size,
                          leading=leading, alignment=TA_LEFT, **kw)


H0 = st('H0', 21, 28, spaceAfter=4)
SUB = st('SUB', 10.5, 15, textColor=GRIS, spaceAfter=14)
H1 = st('H1', 14.5, 20, spaceBefore=16, spaceAfter=7)
H2 = st('H2', 11.5, 16, spaceBefore=11, spaceAfter=5)
P = st('P', 9.6, 14.6, spaceAfter=5)
PS = st('PS', 8.8, 13, textColor=GRIS, spaceAfter=4)
MONO = ParagraphStyle('MONO', parent=ss['Normal'], fontName='Courier', fontSize=8.4,
                      leading=11.6, textColor=TINTA, spaceAfter=4)
AVISO = st('AVISO', 9.6, 14.4, textColor=ROJO, spaceAfter=5)
CELDA = st('CELDA', 8.9, 12.6)
CELDA_B = st('CELDA_B', 8.9, 12.6, textColor=colors.white)


def tabla(datos, anchos, cab=True):
    filas = [[Paragraph(c, CELDA_B if (cab and i == 0) else CELDA) for c in fila]
             for i, fila in enumerate(datos)]
    t = Table(filas, colWidths=anchos, hAlign='LEFT')
    estilo = [
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#c9ccd3')),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]
    if cab:
        estilo += [('BACKGROUND', (0, 0), (-1, 0), TINTA)]
    t.setStyle(TableStyle(estilo))
    return t


def caja(flows, borde=ORO, fondo=FONDO):
    t = Table([[flows]], colWidths=[165 * mm], hAlign='LEFT')
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), fondo),
        ('BOX', (0, 0), (-1, -1), 0.9, borde),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 7),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ]))
    return t


def pasos(items):
    return ListFlowable(
        [ListItem(Paragraph(x, P), leftIndent=16, value=i + 1) for i, x in enumerate(items)],
        bulletType='1', bulletFontName='KR', bulletFontSize=9.6, leftIndent=16, spaceAfter=6)


def pie(canv, doc):
    canv.saveState()
    canv.setFont('KR', 7.6)
    canv.setFillColor(GRIS)
    canv.drawString(22 * mm, 12 * mm, 'Ventago · ARCA Padrón 위임 절차 · 실측 기준 2026-09-26')
    canv.drawRightString(A4[0] - 22 * mm, 12 * mm, '%d' % doc.page)
    canv.setStrokeColor(ORO)
    canv.setLineWidth(1.6)
    canv.line(22 * mm, 16 * mm, A4[0] - 22 * mm, 16 * mm)
    canv.restoreState()


def construir(salida):
    doc = BaseDocTemplate(salida, pagesize=A4, title='ARCA Padron 위임 절차 안내서',
                          author='Ventago', subject='ws_sr_constancia_inscripcion 위임',
                          leftMargin=22 * mm, rightMargin=22 * mm,
                          topMargin=20 * mm, bottomMargin=22 * mm)
    marco = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='n')
    doc.addPageTemplates([PageTemplate(id='base', frames=[marco], onPage=pie)])
    doc.build(cuerpo())


def cuerpo():
    f = []
    A = f.append

    # ── 표지 ───────────────────────────────────────────────────────────────
    A(Paragraph('ARCA Padrón 위임 절차 안내서', H0))
    A(Paragraph('CUIT 를 치면 이름·주소가 자동으로 채워지게 하려면 무엇을 해야 하는가<br/>'
                'Ventago · Phase 94 선행 작업 · 실측 기준 2026-09-26', SUB))

    A(caja([
        Paragraph('3분 요약', H2),
        Paragraph('바꿀 것은 <b>인증서가 아니라 인증서에 붙은 «서비스별 권한»</b> 하나입니다. '
                  'ARCA 는 접속 티켓을 <b>(인증서, 서비스) 쌍</b>으로 발급하는데, 우리 인증서는 '
                  '<b>청구서 발행(wsfe)</b> 에만 권한이 있습니다. 거기에 '
                  '<b>Consulta constancia de inscripción</b> 을 하나 더 붙이면 됩니다.', P),
        Paragraph('포털에서 <b>5~10분</b>이면 끝나는 작업이고, 코드는 이미 다 준비돼 있습니다. '
                  '위임이 없으면 코드를 아무리 붙여도 <b>한 줄도 동작하지 않습니다</b> — '
                  'ARCA 가 티켓 자체를 주지 않기 때문입니다.', P),
        Paragraph('★ 그리고 <b>인증서 갱신이 24일 뒤(2026-10-20)</b>입니다. '
                  '§5 에 갱신 절차도 같이 넣었습니다.', AVISO),
    ]))

    # ── 1. 지금 상태 ────────────────────────────────────────────────────────
    A(Paragraph('1. 지금 우리 상태 (전부 운영 실측)', H1))
    A(Paragraph('아래 값은 2026-09-26 에 운영 서버의 인증서 파일과 ARCA 응답에서 직접 읽은 것입니다. '
                '추측한 값은 없습니다.', PS))
    A(tabla([
        ['항목', '값', '출처'],
        ['CUIT (대표자)', '20950928434', '인증서 serialNumber'],
        ['인증서 별칭 (Alias / CN)', '<b>CNCOOLSISTEMA2024</b>', '인증서 subject'],
        ['발급자', 'CN=Computadores, O=AFIP, C=AR<br/>= <b>운영</b>(Test 아님)', '인증서 issuer'],
        ['유효기간', '2024-10-20 → <b>2026-10-20</b> (남은 <b>24일</b>)', '인증서 validTo'],
        ['현재 위임된 서비스', '<b>wsfe</b> (청구서 발행) 뿐', '토큰 폴더에 TA-…-wsfe.xml 하나만'],
        ['붙여야 하는 서비스', '<b>ws_sr_constancia_inscripcion</b>', 'ARCA 매뉴얼 v3.7 §2.4'],
    ], [42 * mm, 72 * mm, 51 * mm]))

    # ── 2. 먼저 알아야 할 것 ────────────────────────────────────────────────
    A(Paragraph('2. 먼저 알아야 할 것 — ARCA 공식 답변', H1))
    A(Paragraph('이 두 가지가 「지금 쓰는 인증서를 건드려도 되는가」에 대한 답입니다. '
                'ARCA 공식 문서의 FAQ 원문입니다.', PS))

    A(caja([
        Paragraph('Q. 같은 computador(인증서)를 여러 Webservice 에 쓸 수 있나?', H2),
        Paragraph('<b>«Sí. El mismo computador puede ser utilizado para distintos Webservices '
                  'provistos por AFIP.»</b>', MONO),
        Paragraph('→ <b>청구서 발행 인증서에 Padrón 을 더 붙여도 됩니다.</b> 발행은 영향을 받지 않습니다. '
                  '새 인증서를 만들 필요도 없습니다.', P),
    ], borde=colors.HexColor('#2e7d32'), fondo=colors.HexColor('#eef6ef')))

    A(Spacer(1, 5))
    A(caja([
        Paragraph('Q. 같은 인증서를 두 대의 기계에서 동시에 쓸 수 있나?', H2),
        Paragraph('<b>«No. … Durante ese período de validez, ese computador no podrá solicitar '
                  'otro ticket de inicio de sesión para el mismo Webservice.»</b>', MONO),
        Paragraph('→ 이것이 Ventago 코드에 <b>CUIT별 캐시가 «선택이 아니라 필수»</b> 인 이유입니다. '
                  '같은 서비스 티켓을 유효기간 안에 두 번 요청하면 ARCA 가 거부하고, '
                  '잘못 다루면 <b>최대 12시간 발행 불가</b>가 됩니다. '
                  '(운영에서 발행 게이트웨이와 토큰 파일을 공유하고 있습니다.)', P),
    ], borde=ROJO, fondo=colors.HexColor('#fdeceb')))

    A(PageBreak())

    # ── 3. 절차 ─────────────────────────────────────────────────────────────
    A(Paragraph('3. 절차 — Padrón 서비스 위임 (화면 순서대로)', H1))
    A(Paragraph('필요 조건: <b>클라베 피스칼 «nivel 3»</b>, 그리고 그 CUIT 의 '
                '<b>Administrador de Relaciones</b> 권한. (공식 문서 §1.1)', PS))
    A(Paragraph('★ 스페인어 문구는 <b>화면에 그대로 나오는 글자</b>입니다. 찾을 때 이 글자를 보세요.', PS))

    A(Paragraph('3-1. 로그인', H2))
    A(pasos([
        '<b>www.arca.gob.ar</b> 로 들어가 <b>«Clave Fiscal»</b> 접속 버튼을 누릅니다.',
        'CUIT 을 <b>하이픈 없이</b> 입력합니다 → <b>20950928434</b>. 그 다음 <b>Clave</b> 칸에 비밀번호.',
        '<b>«INGRESAR»</b> 버튼을 누릅니다. 사용 가능한 서비스 목록이 펼쳐집니다.',
    ]))
    A(Paragraph('⚠ 회사(persona jurídica) 클라베가 아니라 <b>사람(persona física)</b> 클라베로 '
                '들어가야 하는 경우가 있습니다. 목록에 다음 서비스가 안 보이면 그 이유입니다.', PS))

    A(Paragraph('3-2. 서비스 열기', H2))
    A(pasos([
        '서비스 목록에서 <b>«Administración de Relaciones de Clave Fiscal»</b> 을 찾습니다. '
        '(경우에 따라 <b>«Subadministrador de Relaciones de Clave Fiscal»</b> 로 보입니다. '
        '안 보이면 <b>«Ver todos»</b> 를 누릅니다.)',
        '들어가면 <b>«누구 이름으로 거래할 것인가»</b> 를 먼저 고르는 화면이 나옵니다. '
        '펼침 목록에서 <b>CUIT 20950928434 에 해당하는 대상</b>을 고릅니다.',
    ]))
    A(caja([
        Paragraph('★ 여기서 <b>사람 이름</b>을 고르면 그 사람 명의로 권한이 붙습니다. '
                  '우리 인증서의 주인(CUIT 20950928434)을 골라야 합니다. '
                  '공식 문서의 경고 원문: «los servicios autorizados serán autorizados para operar '
                  'en nombre de JUAN JOSE ESQUIVEL, y no en nombre de SERVICIOS GENERALES S.A.»', P),
    ]))

    A(Paragraph('3-3. 메뉴에서 «Nueva Relación» 을 고른다', H2))
    A(Paragraph('메뉴에 <b>네 개</b>의 선택지가 있습니다. 헷갈리기 쉬우니 표로 정리합니다.', P))
    A(tabla([
        ['메뉴', '무엇', '이번에 쓰나'],
        ['<b>Adherir Servicio</b>', '나 자신이 쓸 서비스를 추가', '아니오'],
        ['<b>Nueva Relación</b>', '<b>Representado 와 Representante 를 골라</b> 권한을 만든다',
         '<b>★ 예 — 이것</b>'],
        ['<b>Consultar</b>', '이미 준 권한을 보고 <b>Revocar</b>(회수)', '나중에 취소할 때'],
        ['(네 번째)', '남이 나에게 준 위임을 <b>Aceptar</b>', '아니오'],
    ], [38 * mm, 90 * mm, 37 * mm]))
    A(Paragraph('이번 작업은 <b>우리 인증서에</b> 권한을 붙이는 것이라 «Nueva Relación» 입니다. '
                '«Adherir Servicio» 는 Representante 를 고를 수 없어 이 일에 쓸 수 없습니다.', PS))

    A(Paragraph('3-4. 서비스를 찾는다', H2))
    A(pasos([
        '<b>Representado</b> 펼침 목록 — 관리 대상이 하나뿐이면 <b>이미 선택된 채 비활성</b>으로 '
        '나옵니다. 정상입니다.',
        '서비스 검색으로 갑니다. 서비스는 <b>«Webservices» 라는 묶음(agrupación)</b> 안에 있습니다. '
        '먼저 그 묶음을 고릅니다.',
        '그 안에서 <b>«Consulta constancia de inscripción»</b> 을 찾습니다. '
        '기술 이름은 <b>ws_sr_constancia_inscripcion</b> 입니다.',
    ]))
    A(caja([
        Paragraph('★ 찾을 때의 팁 — <b>«Padrón» 으로 검색하면 여러 개가 나옵니다.</b> '
                  'ARCA 에는 Padrón 계열 서비스가 여러 종(A4·A5·A10·A13 등) 있습니다. '
                  '우리가 필요한 것은 <b>constancia de inscripción</b> 이라는 말이 들어간 것 하나입니다. '
                  '확실히 하려면 기술 이름 <b>ws_sr_constancia_inscripcion</b> 이 맞는지 보세요.', P),
        Paragraph('★ <b>«Facturación Electrónica»(wsfe) 는 이미 되어 있으니 건드리지 마세요.</b> '
                  '다시 누를 필요 없습니다.', AVISO),
    ]))

    A(Paragraph('3-5. Representante 를 «우리 인증서» 로 고른다', H2))
    A(Paragraph('서비스를 고르면 <b>«Selección del Representante a autorizar»</b> 화면이 열립니다. '
                '여기가 이 작업의 핵심입니다.', P))
    A(pasos([
        '두 가지 방법이 보입니다 — (i) <b>내 computador fiscal 을 고르기</b>, '
        '(ii) 남의 CUIT 을 적어 제3자에게 맡기기.',
        '<b>(i) 을 씁니다.</b> 펼침 목록에서 <b>CNCOOLSISTEMA2024</b> 를 고릅니다. '
        '(이것이 지금 청구서를 발행하고 있는 그 인증서입니다.)',
        'computador fiscal 을 고르면 <b>CUIT 입력칸이 자동으로 비활성</b>됩니다. 정상입니다.',
        '<b>«Confirmar»</b> 를 누릅니다.',
        '화면이 갱신되며 선택 내용이 요약됩니다. <b>한 번 더 검토</b>한 뒤 '
        '<b>«Confirmar»</b> 를 다시 누릅니다. (확인이 <b>두 번</b>입니다.)',
        '완료되면 ARCA 가 증빙 <b>F3283/E</b> 를 발급합니다. <b>저장해 두세요.</b>',
    ]))

    A(Spacer(1, 10))

    # ── 4. 확인 ─────────────────────────────────────────────────────────────
    A(Paragraph('4. 제대로 됐는지 확인하는 방법', H1))
    A(Paragraph('포털 화면으로 눈대중하지 말고 <b>실제로 티켓이 나오는지</b>를 봅니다. '
                'Ventago 에 그 진단이 이미 들어 있습니다.', P))
    A(caja([
        Paragraph('superadmin 으로 로그인한 뒤:', PS),
        Paragraph('GET https://newapi.coolsistema.com/api/afip/padron/diagnose', MONO),
        Paragraph('응답에서 이 값을 봅니다:', PS),
        Paragraph('"ticketObtained": true    ← <b>이것이 true 면 위임이 된 것입니다</b><br/>'
                  '"queryOk": true           ← 실제 조회까지 성공<br/>'
                  '"ticketError": null', MONO),
    ]))
    A(Paragraph('★ <b>«화면에서 봤다» 보다 이 값이 확실합니다.</b> 여기서 성공하면 위임이 완료된 것이고, '
                '실패하면 그 이유가 <b>ticketError</b> 에 그대로 적혀 나옵니다.', P))
    A(Paragraph('이 값이 true 가 되면 저에게 알려주세요. 그때부터 Phase 94 의 나머지 '
                '(CUIT 검증숫자 판정 → ARCA 폴백 배선 → 화면 연결)를 진행합니다.', P))

    # ── 5. 인증서 갱신 ──────────────────────────────────────────────────────
    A(Paragraph('5. 같이 해야 하는 일 — 인증서 갱신 (D-24)', H1))
    A(Paragraph('인증서가 <b>2026-10-20</b> 에 만료됩니다. 그날이 지나면 '
                '<b>청구서 발행이 멈춥니다.</b> 위임과 별개 작업이지만 시점이 겹칩니다.', AVISO))

    A(caja([
        Paragraph('★★ 좋은 소식 — 순서에 구애받지 않습니다', H2),
        Paragraph('ARCA 의 권한은 <b>인증서 파일</b>이 아니라 '
                  '<b>Alias(= computador fiscal)</b> 에 붙습니다. '
                  '갱신할 때 <b>같은 Alias</b>(CNCOOLSISTEMA2024)를 쓰면 '
                  '<b>이미 준 권한이 그대로 살아남습니다.</b>', P),
        Paragraph('→ 그래서 <b>Padrón 위임을 지금 먼저 해도 되고</b>, 갱신 뒤에 해도 됩니다. '
                  '갱신 때 위임을 다시 걸 필요는 <b>없습니다.</b>', P),
    ], borde=colors.HexColor('#2e7d32'), fondo=colors.HexColor('#eef6ef')))

    A(Paragraph('5-1. 갱신 절차 (공식)', H2))
    A(pasos([
        'Ventago 에서 <b>Configuración › Facturación › 인증서 카드</b> 로 갑니다. '
        '<b>«Renovar (generar CSR nuevo)»</b> 버튼으로 CSR 을 만들고 복사/다운로드합니다. '
        '(터미널이나 OpenSSL 을 직접 쓸 필요 없습니다.)',
        'ARCA 포털에서 서비스 <b>«Administración de Certificados Digitales»</b> 을 엽니다.',
        '★ <b>«Agregar Alias» 가 아니라 «Agregar Certificado»</b> 를 누릅니다. '
        '그리고 <b>같은 Alias</b>(CNCOOLSISTEMA2024)를 그대로 적고 새 CSR 을 올립니다. '
        '— 이것이 권한을 유지하는 방법입니다.',
        '발급되면 <b>«Descargar»</b> 로 <b>.crt</b> 파일을 받습니다.',
        'Ventago 의 같은 화면에서 <b>«Subir certificado (.crt)»</b> 로 올립니다. '
        'Ventago 가 CUIT 일치·CSR 대응·만료일을 <b>그 자리에서</b> 검증합니다.',
    ]))
    A(Paragraph('공식 문서 원문: «deberá utilizar el botón “Agregar Certificado”. … donde deberá '
                'consignar el mismo Alias y enviar un nuevo CSR»', PS))
    A(Paragraph('⚠ 운영/테스트를 섞지 마세요. 발급자가 <b>«Computadores»</b> 면 운영, '
                '<b>«Computadores Test»</b> 면 테스트입니다. 우리 것은 운영입니다.', PS))

    A(PageBreak())

    # ── 6. 함정 ─────────────────────────────────────────────────────────────
    A(Paragraph('6. 함정 — 미리 알고 가면 몇 시간을 아낍니다', H1))
    A(Paragraph('아래는 2026-09-26 에 실제로 확인하면서 겪은 것들입니다.', PS))

    A(tabla([
        ['함정', '실측 사실', '그래서'],
        ['「인증서를 바꾸면 되지 않나」',
         '이미 그 인증서를 쓰고 있습니다. 막는 것은 <b>서비스별 권한</b>입니다.',
         '인증서를 새로 만들지 마세요. 권한 한 줄만 추가'],
        ['「인증서 없이 되는 길이 있을 것」',
         '공개 REST 3경로를 운영 서버에서 직접 호출 → <b>전부 404</b>',
         '우회로 없음. 위임이 유일한 길'],
        ['공식 매뉴얼의 주소가<br/>안 열린다',
         '매뉴얼 v3.7 은 <b>aws.arca.gov.ar</b> 를 적어 놨지만 <b>DNS 가 안 풀립니다.</b> '
         '실제로 사는 것은 구 <b>aws.afip.gov.ar</b> (WSDL 200)',
         '<b>코드를 «고치면» 오히려 깨집니다.</b> 지금 그대로 둡니다'],
        ['Padrón A5 가 폐지됐다는 글',
         '2차 자료의 혼동입니다. 매뉴얼 v3.7(2025-07)이 '
         '<b>personaServiceA5</b> 를 현재 경로로 명시합니다',
         '우리 코드의 서비스 id·경로가 맞습니다'],
        ['토큰 파일은 「캐시」다',
         '사실은 <b>잠금</b>입니다. 발행 게이트웨이와 공유합니다',
         '복사해 갈라 놓으면 최대 12시간 발행 불가'],
    ], [33 * mm, 78 * mm, 54 * mm]))

    A(Paragraph('7. 이 문서가 못 하는 것 (솔직하게)', H1))
    A(Paragraph('ARCA 포털은 <b>로그인 뒤에만</b> 보입니다. 저는 그 안에 들어갈 수 없으므로, '
                '여기 적은 화면 문구는 <b>ARCA 공식 문서 원문</b>에서 가져온 것입니다. '
                '공식 문서의 화면 그림은 오래된 판(2011)이라 <b>버튼 색·배치는 지금과 다를 수 있습니다.</b> '
                '<b>글자</b>는 그대로 쓰이고 있습니다.', P))
    A(Paragraph('→ 화면이 문서와 다르면, <b>버튼 모양이 아니라 위 표의 «글자»를 찾으세요.</b> '
                '그리고 다르게 생긴 화면을 만나면 사진을 보내 주시면 이 문서를 고치겠습니다.', P))

    A(Paragraph('8. 출처 (전부 ARCA 공식)', H1))
    A(tabla([
        ['문서', '버전/날짜', '주소'],
        ['Delegación de Webservices con el<br/>Administrador de Relaciones',
         '1.1.0', 'arca.gob.ar/ws/WSAA/<br/>ADMINREL.DelegarWS.pdf'],
        ['Generación de Certificados Digitales<br/>para Utilización con Webservices',
         '—', 'arca.gob.ar/ws/WSAA/<br/>WSAA.ObtenerCertificado.pdf'],
        ['Constancia de Inscripción<br/>ws_sr_constancia_inscripcion',
         '<b>3.7 · 2025-07</b>', 'arca.gob.ar/ws/WSCI/<br/>manual_ws_sr_ws_constancia_inscripcion_v3.7.pdf'],
        ['WSASS: Cómo adherirse al servicio',
         '2025-09-19', 'arca.gob.ar/ws/WSASS/<br/>WSASS_como_adherirse.pdf'],
        ['인증서·WS 문서 색인', '—', 'arca.gob.ar/ws/documentacion/certificados.asp'],
    ], [58 * mm, 26 * mm, 81 * mm]))
    A(Paragraph('기술 문의처(공식): sri@arca.gob.ar — 제목에 WS 이름과 환경(Producción/Homologación)을 '
                '적고 request/response 를 첨부하라고 매뉴얼이 안내합니다.', PS))

    return f


if __name__ == '__main__':
    destino = os.environ.get('SALIDA', 'ARCA-Padron-위임절차.pdf')
    construir(destino)
    print('생성:', destino, os.path.getsize(destino), 'bytes')
