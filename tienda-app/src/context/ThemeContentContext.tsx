import { createContext, useContext, useMemo } from 'react';
import type { ReactNode } from 'react';
import { DEFAULT_CONTENT } from '@/lib/theme-preset';
import type { StoreThemeContent } from '@/types/shop';

// 테마 content 를 트리 전체에 내려주는 단일 진입점.
// Provider 밖에서 호출돼도 DEFAULT_CONTENT 를 반환해 절대 크래시하지 않는다(공개몰은 안 깨지는 게 최우선).
const ThemeContentContext = createContext<StoreThemeContent>(DEFAULT_CONTENT);

export function ThemeContentProvider({
  content,
  children,
}: {
  content: StoreThemeContent | null | undefined;
  children: ReactNode;
}) {
  const value = useMemo(() => content ?? DEFAULT_CONTENT, [content]);

  return (
    <ThemeContentContext.Provider value={value}>
      {children}
    </ThemeContentContext.Provider>
  );
}

export function useThemeContent(): StoreThemeContent {
  return useContext(ThemeContentContext);
}
