#!/usr/bin/env node
/**
 * VentaGO 매뉴얼 docx 빌더 (ES + KO)
 *
 * 사용법:
 *   NODE_PATH=<docx 설치 경로> node tools/manuales/build-manual.js <content-파일> [출력디렉터리]
 *   예: node tools/manuales/build-manual.js content-ventas.js docs/manuales
 *
 * 캡처: docs/manual-captures/<captureDir>/<capture>.png 이 존재하면 삽입,
 *       없으면 자리표시자 박스를 넣는다. 캡처 추가 후 재실행하면 완성본이 나온다.
 */

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, ImageRun, HeadingLevel, AlignmentType,
  LevelFormat, BorderStyle, TableOfContents, PageBreak, Header, Footer, PageNumber,
} = require('docx');

const ROOT = path.resolve(__dirname, '..', '..');
const contentFile = process.argv[2];
if (!contentFile) {
  console.error('사용법: node build-manual.js <content-파일> [출력디렉터리]');
  process.exit(1);
}
const content = require(path.resolve(__dirname, contentFile));
const outDir = path.resolve(ROOT, process.argv[3] || 'docs/manuales');
const capturesDir = path.join(ROOT, 'docs', 'manual-captures', content.captureDir);

// PNG IHDR 에서 픽셀 크기 읽기 (비율 유지 삽입용)
function pngSize(buf) {
  if (buf.length < 24 || buf.readUInt32BE(12) !== 0x49484452) return null;

  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

const CONTENT_W = 9360; // US Letter, 1in 여백 기준 DXA
const IMG_MAX_PT = 468; // 6.5in (docx-js transformation 단위: pt 근사 px)

function buildDoc(lang) {
  const font = lang === 'ko' ? 'Malgun Gothic' : 'Arial';
  const t = (obj) => obj[lang];
  const kids = [];

  // ── 표지 ──
  kids.push(
    new Paragraph({ spacing: { before: 3000 } }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: 'VentaGO', bold: true, size: 72, color: 'B8730A' })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 400 },
      children: [new TextRun({ text: t(content.title), bold: true, size: 48 })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 200 },
      children: [new TextRun({ text: t(content.subtitle), size: 28, color: '666666' })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 2400 },
      children: [new TextRun({ text: new Date().toISOString().slice(0, 10), size: 22, color: '999999' })],
    }),
    new Paragraph({ children: [new PageBreak()] }),
  );

  // ── 목차 ──
  kids.push(
    new Paragraph({
      heading: HeadingLevel.HEADING_1,
      children: [new TextRun(lang === 'ko' ? '목차' : 'Índice')],
    }),
    new TableOfContents(lang === 'ko' ? '목차' : 'Índice', { hyperlink: true, headingStyleRange: '1-2' }),
    new Paragraph({ children: [new PageBreak()] }),
  );

  // ── 소개 ──
  kids.push(
    new Paragraph({
      heading: HeadingLevel.HEADING_1,
      children: [new TextRun(lang === 'ko' ? '소개' : 'Introducción')],
    }),
    new Paragraph({ spacing: { after: 240 }, children: [new TextRun(t(content.intro))] }),
  );

  // ── 주제들 ──
  content.topics.forEach((topic, i) => {
    kids.push(
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        pageBreakBefore: true,
        children: [new TextRun(`${i + 1}. ${t(topic.title)}`)],
      }),
      new Paragraph({ spacing: { after: 200 }, children: [new TextRun(t(topic.intro))] }),
    );

    // 캡처 (있으면 이미지, 없으면 자리표시자)
    const capPath = path.join(capturesDir, `${topic.capture}.png`);
    if (fs.existsSync(capPath)) {
      const buf = fs.readFileSync(capPath);
      const size = pngSize(buf) || { w: 1600, h: 900 };
      const w = Math.min(IMG_MAX_PT, size.w);
      const h = Math.round((w / size.w) * size.h);
      kids.push(
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 200 },
          children: [new ImageRun({
            type: 'png',
            data: buf,
            transformation: { width: w, height: h },
            altText: { title: topic.capture, description: t(topic.title), name: topic.capture },
          })],
        }),
      );
    } else {
      kids.push(
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { before: 120, after: 200 },
          // 주의: docx-js 는 4면 테두리를 top,bottom,left,right 순으로 직렬화해
          // OOXML 스키마 순서를 위반함 → 상/하 테두리만 사용 (top→bottom 은 유효)
          border: {
            top: { style: BorderStyle.DASHED, size: 6, color: 'B8730A', space: 8 },
            bottom: { style: BorderStyle.DASHED, size: 6, color: 'B8730A', space: 8 },
          },
          children: [new TextRun({
            text: (lang === 'ko' ? '캡처 예정: ' : 'Captura pendiente: ') + topic.capture,
            color: 'B8730A',
            italics: true,
          })],
        }),
      );
    }

    // 단계 (주제별 독립 번호 — reference 를 주제별로 분리)
    topic.steps.forEach((step) => {
      kids.push(
        new Paragraph({
          numbering: { reference: `steps-${topic.id}`, level: 0 },
          spacing: { after: 100 },
          children: [new TextRun(t(step))],
        }),
      );
    });

    // 팁
    (topic.tips || []).forEach((tip) => {
      kids.push(
        new Paragraph({
          spacing: { before: 160, after: 100 },
          border: { left: { style: BorderStyle.SINGLE, size: 12, color: 'B8730A', space: 8 } },
          children: [
            new TextRun({ text: lang === 'ko' ? 'TIP  ' : 'TIP  ', bold: true, color: 'B8730A' }),
            new TextRun(t(tip)),
          ],
        }),
      );
    });
  });

  return new Document({
    styles: {
      default: { document: { run: { font, size: 22 } } },
      paragraphStyles: [
        {
          id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
          run: { size: 32, bold: true, font, color: '1F1F33' },
          paragraph: { spacing: { before: 240, after: 240 }, outlineLevel: 0 },
        },
        {
          id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
          run: { size: 26, bold: true, font, color: '1F1F33' },
          paragraph: { spacing: { before: 180, after: 180 }, outlineLevel: 1 },
        },
      ],
    },
    numbering: {
      config: content.topics.map((topic) => ({
        reference: `steps-${topic.id}`,
        levels: [{
          level: 0,
          format: LevelFormat.DECIMAL,
          text: '%1.',
          alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } },
        }],
      })),
    },
    sections: [{
      properties: {
        page: {
          size: { width: 12240, height: 15840 },
          margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
        },
      },
      headers: {
        default: new Header({
          children: [new Paragraph({
            alignment: AlignmentType.RIGHT,
            children: [new TextRun({ text: `VentaGO — ${t(content.title)}`, size: 18, color: '999999' })],
          })],
        }),
      },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [new TextRun({ children: [PageNumber.CURRENT], size: 18, color: '999999' })],
          })],
        }),
      },
      children: kids,
    }],
  });
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  for (const lang of ['es', 'ko']) {
    const doc = buildDoc(lang);
    const buf = await Packer.toBuffer(doc);
    const out = path.join(outDir, `${content.fileBase}_${lang.toUpperCase()}.docx`);
    fs.writeFileSync(out, buf);
    console.log(`[build-manual] ${out} (${(buf.length / 1024).toFixed(0)} KB)`);
  }
})();
