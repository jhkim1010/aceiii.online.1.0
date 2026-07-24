import Benefits from '@/components/sections/Benefits';
import Carousel from '@/components/sections/Carousel';
import DuoBanners from '@/components/sections/DuoBanners';
import Hero from '@/components/sections/Hero';
import Newsletter from '@/components/sections/Newsletter';
import QuizSection from '@/components/sections/QuizSection';
import ReelsSection from '@/components/sections/ReelsSection';
import type { SectionConfig, ShopProduct } from '@/types/shop';

export default function SectionRenderer({
  storeId,
  section,
  initialItems,
}: {
  storeId: number;
  section: SectionConfig;
  initialItems?: ShopProduct[];
}) {
  // 표시 토글이 꺼진 섹션은 DOM 자체를 만들지 않는다(빈 공간 남기지 않음 — display:none 아님)
  if (!section.enabled) return null;

  switch (section.type) {
    case 'hero':
      return <Hero section={section} />;
    case 'benefits':
      return <Benefits section={section} />;
    case 'carousel':
      return (
        <Carousel storeId={storeId} section={section} initialItems={initialItems} />
      );
    case 'duoBanners':
      return <DuoBanners section={section} />;
    case 'newsletter':
      return <Newsletter section={section} />;
    case 'reels':
      return <ReelsSection storeId={storeId} section={section} />;
    case 'quiz':
      return <QuizSection storeId={storeId} section={section} />;
    default:
      // 알 수 없는 타입은 조용히 무시(백엔드 sanitize 가 이미 걸러내지만 방어)
      return null;
  }
}

// 구조별 섹션 게이팅(GATED_BY_MACRO)은 여기서 처리하지 않는다 — 게이팅은 에디터(표면 A)의
// 안내 UI 이고(Plan 61-10), 실제 렌더 억제는 Plan 61-09 의 index.tsx 가 macrostructure 에
// 따라 sections 배열을 필터링한 뒤 이 컴포넌트를 호출하는 방식으로 담당한다.
