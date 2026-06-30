import type { GetServerSideProps } from 'next';

// 루트(/) → 기본 매장 카탈로그로 리디렉트. 멀티매장은 /:storeId 직접 접근.
export const getServerSideProps: GetServerSideProps = async () => {
  const storeId = process.env.NEXT_PUBLIC_DEFAULT_STORE_ID || '25';

  return {
    redirect: { destination: `/${storeId}`, permanent: false },
  };
};

export default function Home() {
  return null;
}
