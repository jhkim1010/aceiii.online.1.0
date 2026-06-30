/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // 공개몰 — 서버사이드에서 백엔드 공개 API 호출(SSR). 빌드는 standalone 으로 Docker 경량화.
  output: 'standalone',
  images: {
    // 백엔드 MinIO 가 서빙하는 상품 이미지 호스트 허용 (next/Image)
    remotePatterns: [
      { protocol: 'https', hostname: 'newapi.coolsistema.com' },
      { protocol: 'http', hostname: 'localhost' },
    ],
  },
};

module.exports = nextConfig;
