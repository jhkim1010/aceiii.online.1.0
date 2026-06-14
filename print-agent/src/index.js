/**
 * VentaGO 프린트 에이전트
 * WebSocket으로 백엔드에서 print_invoice 이벤트를 수신하고
 * ESC/POS로 열감지 프린터에 출력
 */
const { io } = require('socket.io-client');
const config = require('../config.json');
const { formatInvoice, formatTempTicketHtml } = require('./formatter');
const { printReceipt, printImage, testConnection } = require('./printer');
const { renderHtmlToPng } = require('./renderer-engine');

// WebSocket 연결
const socket = io(`${config.apiUrl}/realtime`, {
  reconnection: true,
  reconnectionDelay: 3000,
  reconnectionAttempts: Infinity,
});

// 연결 성공
socket.on('connect', () => {
  console.log(`✅ WebSocket 연결 성공 (id: ${socket.id})`);
  // apiKey로 지점 등록
  socket.emit('register_api_key', { apiKey: config.apiKey });
  console.log(`🔑 API Key 등록: ${config.apiKey}`);
});

// 환영 메시지
socket.on('welcome', (data) => {
  console.log(`👋 ${data.message}`);
});

// 영수증 출력 이벤트 수신
socket.on('print_invoice', async (invoiceData) => {
  const ticketNum = invoiceData?.invoice?.number || 'desconocido';
  console.log(`🖨️  영수증 출력 요청 수신: ${ticketNum}`);

  try {
    // JSON → ESC/POS 포맷 변환
    const formatted = formatInvoice(invoiceData, config.printer.width);
    // 프린터에 출력
    await printReceipt(formatted, config.printer);
    console.log(`✅ 출력 완료: ${ticketNum}`);
    // 성공 확인 전송
    socket.emit('print_confirmation', {
      success: true,
      invoiceNumber: ticketNum,
      printedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error(`❌ 출력 실패: ${ticketNum}`, error.message);
    // 실패 확인 전송
    socket.emit('print_confirmation', {
      success: false,
      invoiceNumber: ticketNum,
      error: error.message,
    });
  }
});

// Phase 39: 식당 comanda(주방 전표) + resumen(cuenta/영수증) 출력
// backend print.service.emitPrintTemp(branchId, data) 가 보내는 print_temp 수신
// formatTempTicketHtml → renderHtmlToPng(576px) → printImage 파이프라인 (print-pipeline.js 동일 흐름)
// fire-and-forget: backend 는 응답을 기다리지 않으므로 에러는 console 로만 남긴다 (T-39-06 mitigation)
socket.on('print_temp', async (tempData) => {
  console.log(`🍽️  식당 임시전표 출력 요청 수신 (mesa: ${tempData?.tableName || '?'})`);

  try {
    // comanda/resumen HTML 생성 (items/variants/totals 렌더)
    const html = formatTempTicketHtml(tempData);

    // HTML → PNG (80mm @ 203dpi = 576px), Phase 38 print_qr 와 동일 파이프라인
    const pngBuffer = await renderHtmlToPng(html, 576);

    // PNG → 감열 프린터 출력 (dev 시 ~/Desktop/print-debug-*.png 저장)
    await printImage(pngBuffer, config.printer);

    console.log('✅ 식당 임시전표 출력 완료');
  } catch (error) {
    console.error('❌ 식당 임시전표 출력 실패:', error.message);
  }
});

// 연결 끊김
socket.on('disconnect', (reason) => {
  console.log(`🔴 WebSocket 연결 끊김: ${reason}`);
});

// 재연결 시도
socket.on('reconnect_attempt', (attempt) => {
  console.log(`🔄 재연결 시도 #${attempt}...`);
});

// 에러 처리
socket.on('connect_error', (error) => {
  console.error(`❌ 연결 오류: ${error.message}`);
});

// 시작 시 프린터 연결 테스트
(async () => {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  VentaGO 프린트 에이전트 v1.0');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`📡 서버: ${config.apiUrl}`);
  console.log(`🖨️  프린터: ${config.printer.type} (${config.printer.type === 'network' ? config.printer.host + ':' + config.printer.port : 'USB'})`);
  console.log('');

  try {
    await testConnection(config.printer);
    console.log('✅ 프린터 연결 테스트 성공');
  } catch (error) {
    console.warn(`⚠️  프린터 연결 테스트 실패: ${error.message}`);
    console.warn('   프린터가 꺼져있거나 설정이 잘못되었을 수 있습니다.');
    console.warn('   WebSocket 수신은 계속 대기합니다.');
  }
  console.log('');
})();
