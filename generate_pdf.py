#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VentaGO 프로젝트 구조 및 동작 방식 PDF 생성 스크립트
"""

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import os

def create_pdf():
    """PDF 문서 생성"""
    filename = "VentaGO_프로젝트_구조_및_동작방식.pdf"
    doc = SimpleDocTemplate(filename, pagesize=A4)
    story = []
    
    # 한글 폰트 등록
    korean_font_paths = [
        '/System/Library/Fonts/Supplemental/AppleGothic.ttf',
        '/System/Library/Fonts/AppleSDGothicNeo.ttc',
        '/Library/Fonts/AppleGothic.ttf',
    ]
    
    korean_font_name = 'KoreanFont'
    korean_font_bold_name = 'KoreanFontBold'
    
    # 폰트 파일 찾기 및 등록
    font_registered = False
    for font_path in korean_font_paths:
        if os.path.exists(font_path):
            try:
                pdfmetrics.registerFont(TTFont(korean_font_name, font_path))
                pdfmetrics.registerFont(TTFont(korean_font_bold_name, font_path))
                font_registered = True
                print(f"한글 폰트 등록 성공: {font_path}")
                break
            except Exception as e:
                print(f"폰트 등록 실패 ({font_path}): {e}")
                continue
    
    if not font_registered:
        print("경고: 한글 폰트를 찾을 수 없습니다. 기본 폰트를 사용합니다.")
        korean_font_name = 'Helvetica'
        korean_font_bold_name = 'Helvetica-Bold'
    
    # 스타일 정의
    styles = getSampleStyleSheet()
    
    # 커스텀 스타일
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=colors.HexColor('#1a237e'),
        spaceAfter=30,
        alignment=TA_CENTER,
        fontName=korean_font_bold_name
    )
    
    heading_style = ParagraphStyle(
        'CustomHeading',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=colors.HexColor('#283593'),
        spaceAfter=12,
        spaceBefore=20,
        fontName=korean_font_bold_name
    )
    
    subheading_style = ParagraphStyle(
        'CustomSubHeading',
        parent=styles['Heading3'],
        fontSize=14,
        textColor=colors.HexColor('#3949ab'),
        spaceAfter=10,
        spaceBefore=15,
        fontName=korean_font_bold_name
    )
    
    normal_style = ParagraphStyle(
        'CustomNormal',
        parent=styles['Normal'],
        fontSize=11,
        leading=16,
        alignment=TA_JUSTIFY,
        fontName=korean_font_name
    )
    
    code_style = ParagraphStyle(
        'CustomCode',
        parent=styles['Code'],
        fontSize=9,
        leading=12,
        fontName='Courier',
        leftIndent=20,
        rightIndent=20,
        backColor=colors.HexColor('#f5f5f5')
    )
    
    # 제목
    story.append(Paragraph("VentaGO 프로젝트 구조 및 동작 방식", title_style))
    story.append(Spacer(1, 0.3*inch))
    
    # 1. 프로젝트 개요
    story.append(Paragraph("1. 프로젝트 개요", heading_style))
    story.append(Paragraph(
        "VentaGO는 상점(매장)의 판매, 재고, 상품 관리를 위한 POS/ERP 시스템입니다. "
        "이 프로젝트는 npm workspaces를 사용하는 모노레포 구조로 구성되어 있으며, "
        "백엔드와 프론트엔드가 하나의 저장소에서 관리됩니다.",
        normal_style
    ))
    story.append(Spacer(1, 0.2*inch))
    
    # 2. 아키텍처 구조
    story.append(Paragraph("2. 아키텍처 구조", heading_style))
    
    story.append(Paragraph("2.1 모노레포 구조", subheading_style))
    story.append(Paragraph(
        "프로젝트는 npm workspaces를 사용하여 두 개의 워크스페이스로 구성됩니다:",
        normal_style
    ))
    
    # 테이블 생성
    data = [
        ['워크스페이스', '기술 스택', '포트', '설명'],
        ['api-ventago', 'NestJS + PostgreSQL', '5002', '백엔드 API 서버'],
        ['ventago-app', 'Next.js + React', '3000', '프론트엔드 웹 애플리케이션']
    ]
    
    table = Table(data, colWidths=[2*inch, 2.5*inch, 1*inch, 2.5*inch])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#3949ab')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), korean_font_bold_name),
        ('FONTSIZE', (0, 0), (-1, 0), 10),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.HexColor('#e8eaf6')),
        ('GRID', (0, 0), (-1, -1), 1, colors.HexColor('#9fa8da')),
        ('FONTSIZE', (0, 1), (-1, -1), 9),
        ('FONTNAME', (0, 1), (-1, -1), korean_font_name),
    ]))
    story.append(table)
    story.append(Spacer(1, 0.2*inch))
    
    # 3. 백엔드 구조
    story.append(Paragraph("3. 백엔드 구조 (api-ventago)", heading_style))
    
    story.append(Paragraph("3.1 기술 스택", subheading_style))
    tech_stack = [
        "• NestJS 11.x - Node.js 프레임워크",
        "• TypeScript - 타입 안정성",
        "• PostgreSQL - 관계형 데이터베이스",
        "• Sequelize - ORM (Object-Relational Mapping)",
        "• JWT - 인증 토큰",
        "• Passport - 인증 전략"
    ]
    for item in tech_stack:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("3.2 주요 모듈", subheading_style))
    modules = [
        "• Auth - 사용자 인증 및 권한 관리",
        "• Users - 사용자 관리",
        "• Store - 매장 관리",
        "• Products - 상품 관리",
        "• Sales - 판매 관리",
        "• Stock - 재고 관리",
        "• Clients - 고객 관리",
        "• Role - 역할 및 권한 관리",
        "• Audit Log - 감사 로그"
    ]
    for item in modules:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("3.3 데이터베이스 동기화", subheading_style))
    story.append(Paragraph(
        "애플리케이션 시작 시 SyncService가 모든 모델을 순회하며 데이터베이스 테이블을 자동으로 생성합니다. "
        "각 테이블 생성 시 테이블 이름만 간단하게 출력됩니다.",
        normal_style
    ))
    
    story.append(PageBreak())
    
    # 4. 프론트엔드 구조
    story.append(Paragraph("4. 프론트엔드 구조 (ventago-app)", heading_style))
    
    story.append(Paragraph("4.1 기술 스택", subheading_style))
    frontend_stack = [
        "• Next.js 13.x - React 프레임워크",
        "• React 18 - UI 라이브러리",
        "• Material-UI (MUI) - UI 컴포넌트",
        "• Redux Toolkit - 상태 관리",
        "• TypeScript - 타입 안정성",
        "• Axios - HTTP 클라이언트"
    ]
    for item in frontend_stack:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("4.2 주요 기능", subheading_style))
    features = [
        "• 사용자 인증 및 권한 관리",
        "• 매장 관리 대시보드",
        "• 상품 및 재고 관리",
        "• 판매 처리 및 관리",
        "• 고객 관리",
        "• 보고서 및 분석"
    ]
    for item in features:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.2*inch))
    
    # 5. 데이터 흐름
    story.append(Paragraph("5. 데이터 흐름", heading_style))
    
    story.append(Paragraph("5.1 인증 흐름", subheading_style))
    auth_flow = [
        "1. 사용자가 로그인 페이지에서 이메일/사용자명과 비밀번호 입력",
        "2. 프론트엔드가 POST /api/auth/login 요청 전송",
        "3. 백엔드에서 사용자 검증 및 JWT 토큰 생성",
        "4. 토큰을 localStorage에 저장",
        "5. 이후 모든 API 요청에 Authorization 헤더로 토큰 포함"
    ]
    for item in auth_flow:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("5.2 API 요청 흐름", subheading_style))
    api_flow = [
        "1. 프론트엔드 컴포넌트에서 apiConnector 사용",
        "2. Axios 인터셉터가 요청에 토큰 자동 추가",
        "3. 백엔드 NestJS 컨트롤러에서 요청 수신",
        "4. Guard를 통한 인증/권한 검증",
        "5. Service에서 비즈니스 로직 처리",
        "6. Sequelize를 통해 데이터베이스 조작",
        "7. Audit Interceptor가 변경 사항 기록",
        "8. 응답 반환"
    ]
    for item in api_flow:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.2*inch))
    
    # 6. 실행 방법
    story.append(Paragraph("6. 실행 방법", heading_style))
    
    story.append(Paragraph("6.1 개발 환경 설정", subheading_style))
    setup_steps = [
        "1. 의존성 설치: npm install",
        "2. 데이터베이스 설정: PostgreSQL 설치 및 데이터베이스 생성",
        "3. 환경 변수 설정: api-ventago/.env 파일 생성",
        "4. 마이그레이션 실행: npm run db:migrate"
    ]
    for item in setup_steps:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("6.2 개발 서버 실행", subheading_style))
    story.append(Paragraph("두 프로젝트를 동시에 실행:", normal_style))
    story.append(Paragraph("npm run dev", code_style))
    story.append(Spacer(1, 0.1*inch))
    story.append(Paragraph("개별 실행:", normal_style))
    story.append(Paragraph("npm run dev:api  # 백엔드만", code_style))
    story.append(Paragraph("npm run dev:app  # 프론트엔드만", code_style))
    
    story.append(Spacer(1, 0.2*inch))
    
    # 7. 주요 디렉토리 구조
    story.append(Paragraph("7. 주요 디렉토리 구조", heading_style))
    
    story.append(Paragraph("7.1 백엔드 (api-ventago/src)", subheading_style))
    backend_structure = [
        "• app/ - 비즈니스 로직 모듈들",
        "  - auth/ - 인증 관련",
        "  - users/ - 사용자 관리",
        "  - products/ - 상품 관리",
        "  - sales/ - 판매 관리",
        "  - store/ - 매장 관리",
        "• common/ - 공통 유틸리티",
        "• config/ - 설정 파일",
        "• database/ - 데이터베이스 연결 및 동기화"
    ]
    for item in backend_structure:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("7.2 프론트엔드 (ventago-app/src)", subheading_style))
    frontend_structure = [
        "• pages/ - Next.js 페이지 라우팅",
        "• views/ - 주요 뷰 컴포넌트",
        "• components/ - 재사용 가능한 컴포넌트",
        "• services/ - API 서비스",
        "• store/ - Redux 상태 관리",
        "• layouts/ - 레이아웃 컴포넌트",
        "• hooks/ - 커스텀 React 훅"
    ]
    for item in frontend_structure:
        story.append(Paragraph(item, normal_style))
    
    story.append(Spacer(1, 0.2*inch))
    
    # 8. 보안 및 권한 관리
    story.append(Paragraph("8. 보안 및 권한 관리", heading_style))
    
    story.append(Paragraph("8.1 인증", subheading_style))
    story.append(Paragraph(
        "JWT 토큰 기반 인증을 사용합니다. 로그인 시 accessToken과 refreshToken이 발급되며, "
        "모든 API 요청에 Authorization 헤더로 토큰이 포함됩니다.",
        normal_style
    ))
    
    story.append(Spacer(1, 0.15*inch))
    
    story.append(Paragraph("8.2 권한 관리", subheading_style))
    story.append(Paragraph(
        "역할 기반 접근 제어(RBAC)를 구현합니다. 사용자는 역할(Role)을 가지며, "
        "각 역할은 여러 기능(Function)에 대한 권한을 가집니다. "
        "프론트엔드에서는 WithFunctionAccess HOC를 사용하여 권한에 따른 UI 제어를 합니다.",
        normal_style
    ))
    
    story.append(Spacer(1, 0.2*inch))
    
    # 9. 감사 로그
    story.append(Paragraph("9. 감사 로그 (Audit Log)", heading_style))
    story.append(Paragraph(
        "모든 중요한 데이터 변경 사항은 AuditInterceptor를 통해 자동으로 기록됩니다. "
        "생성, 수정, 삭제 작업이 발생할 때마다 사용자, 시간, 변경 내용이 audit_logs 테이블에 저장됩니다.",
        normal_style
    ))
    
    story.append(Spacer(1, 0.2*inch))
    
    # 10. 요약
    story.append(Paragraph("10. 요약", heading_style))
    summary = [
        "• 모노레포 구조로 백엔드와 프론트엔드를 통합 관리",
        "• NestJS와 Next.js를 사용한 풀스택 TypeScript 프로젝트",
        "• PostgreSQL과 Sequelize를 사용한 데이터베이스 관리",
        "• JWT 기반 인증 및 역할 기반 권한 관리",
        "• 자동화된 감사 로그 시스템",
        "• 개발 환경에서 두 서버를 동시에 실행 가능"
    ]
    for item in summary:
        story.append(Paragraph(item, normal_style))
    
    # PDF 생성
    doc.build(story)
    print(f"PDF 파일이 생성되었습니다: {filename}")
    return filename

if __name__ == "__main__":
    try:
        create_pdf()
    except Exception as e:
        print(f"오류 발생: {e}")
        import traceback
        traceback.print_exc()

