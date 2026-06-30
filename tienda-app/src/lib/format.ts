// 가격·할부 표시 유틸 (아르헨티나 페소)
const ars = new Intl.NumberFormat('es-AR', {
  style: 'currency',
  currency: 'ARS',
  maximumFractionDigits: 0,
});

export function money(value: number): string {
  return ars.format(Math.round(value || 0));
}

// "3 cuotas de $7.966 sin interés"
export function cuotas(price: number, n = 3): string {
  return `${n} cuotas de ${money((price || 0) / n)} sin interés`;
}

// 이미지 없는 상품용 부드러운 그라데이션 플레이스홀더(인덱스로 변주)
const GRADIENTS = [
  '#f4d6c2,#e8a87c',
  '#cdd6f0,#9fb0e0',
  '#f0cdda,#dd9fb6',
  '#cfe6dd,#9fd0bf',
  '#e8dcc2,#d8c08a',
  '#d8cdf0,#b9a9e0',
  '#f0d8c2,#e0b896',
  '#cde6f0,#9fcfe0',
];

export function placeholderGradient(seed: number): string {
  const g = GRADIENTS[Math.abs(seed) % GRADIENTS.length];

  return `linear-gradient(135deg, ${g})`;
}
