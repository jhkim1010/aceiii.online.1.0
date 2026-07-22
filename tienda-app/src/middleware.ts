import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// 공개몰 서브도메인 라우팅 — <slug>.coolsistema.com → 내부 /[storeId] 로 rewrite(URL 은 서브도메인 유지).
// slug 해석은 공개 API by-slug 사용. 예약/시스템 서브도메인과 로컬/직접 접근은 통과.

const API_HOST =
  process.env.NEXT_PUBLIC_API_HOST || 'http://localhost:5002/api';

// slug 로 취급하지 않는 서브도메인(정적/시스템)
const RESERVED = new Set([
  'www',
  'shop',
  'tienda',
  'app',
  'new',
  'api',
  'newapi',
]);

// 정적/내부 경로는 미들웨어 제외 (성능)
export const config = {
  matcher: ['/((?!_next/|favicon.ico|robots.txt|.*\\.).*)'],
};

export async function middleware(req: NextRequest): Promise<NextResponse> {
  const host = (req.headers.get('host') || '').split(':')[0];
  const parts = host.split('.');

  // <sub>.<domain>.<tld> 형태만 처리 (localhost / apex 도메인은 통과)
  if (parts.length < 3) return NextResponse.next();

  const sub = parts[0];
  if (!sub || RESERVED.has(sub)) return NextResponse.next();

  // 이미 /[storeId] 숫자 경로면 통과 (중복 rewrite 방지)
  const firstSeg = req.nextUrl.pathname.split('/')[1];
  if (/^\d+$/.test(firstSeg)) return NextResponse.next();

  try {
    const r = await fetch(
      `${API_HOST}/public/shop/by-slug/${encodeURIComponent(sub)}`,
    );
    if (!r.ok) return NextResponse.next();

    const data = (await r.json()) as { storeId?: number };
    if (!data?.storeId) return NextResponse.next();

    const url = req.nextUrl.clone();
    const rest = req.nextUrl.pathname === '/' ? '' : req.nextUrl.pathname;
    url.pathname = `/${data.storeId}${rest}`;

    return NextResponse.rewrite(url);
  } catch {
    // 해석 실패 시 통과(몰이 깨지지 않게)
    return NextResponse.next();
  }
}
