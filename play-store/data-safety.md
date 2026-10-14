# Play Console 답안 — 데이터 보안 · 콘텐츠 등급 · 앱 액세스 (Phase 106)

코드에서 실측한 것만 적었다(2026-10-13). 기능이 바뀌면 이 표도 같이 바꾼다.

## 공통 답

| 질문 | 답 |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (전부 HTTPS — newapi.coolsistema.com) |
| Do you provide a way for users to request that their data is deleted? | **Yes** — 개인정보처리방침 §6 의 메일 (계정 삭제 URL 은 B5 결정 후) |
| Data shared with third parties? | **No** (매장·인프라 제공자는 Play 정의상 "공유" 아님 — 서비스 제공자) |
| Ads | **No ads** |
| Target audience | **18+** (업무용) |
| Content rating 설문 | 카테고리 «Utility, Productivity, Communication, or Other» → 폭력·성·약물·도박·사용자 간 소통·위치 공유 **전부 No** → 예상 등급 *Everyone / 3+* |
| Government app / Financial features | No / No (결제 처리 없음 — 매출 기록만) |
| Health apps | No |

## 앱별 수집 데이터 (Data types → Collected, 목적, 선택 여부)

### Ventago Ventas (mobile-sales-app)
| Play 데이터 유형 | 수집 | 목적 | 필수/선택 | 근거 |
|---|---|---|---|---|
| Personal info › Name, Email address, User IDs | ✓ | App functionality, Account management | 필수 | 로그인·재판매자 가입 |
| Personal info › Address / Other info (DNI) | ✓ | Account management (본인 확인) | 재판매자만 | `reseller_auth_repository.dart` dniPhoto·residenceCert |
| Photos and videos › Photos | ✓ | Account management | 재판매자만 | selfie·서류 업로드 |
| Location › Approximate location | ✓ | App functionality (주 판별) | 선택 | `reseller_home_provider.dart` Geolocator → detectProvince |
| Financial info › Purchase history | ✓ | App functionality | 필수 | 판매 기록 |
| App activity › Other actions | ✓ | App functionality | 필수 | 출퇴근(attendance)·선불(adelanto) |
| Camera (바코드) | ✗ 수집 아님 | — | — | 기기에서만 처리, 전송 안 함 |

### Ventago Admin (tienda-admin-app + Wear OS)
| 유형 | 수집 | 목적 |
|---|---|---|
| Personal info › Name, Email, User IDs | ✓ | Account management |
| Financial info › Purchase history (매장 판매·카하) | ✓ | App functionality |
| Biometrics | ✗ — `local_auth` 는 기기 안에서만 판정, 서버로 안 감 |

### Ventago Despacho (despacho-app)
| Name, User IDs (작업자 로그인) | ✓ | Account management |
| Purchase history (주문·배송 상태) | ✓ | App functionality |
(사진 선택 패키지는 의존성에만 있고 **호출하는 곳 없음** — 수집 아님. 나중에 쓰면 여기 추가)

### Ventago Talleres (talleres-vendor-app)
| Name, Email, User IDs | ✓ | Account management |
| Financial info › Other (정산·지급) | ✓ | App functionality |

### Ventago Superadmin (ventago-admin-app) — 내부 테스트만
| Name, Email, User IDs | ✓ | Account management |
| Financial info (매장·구독) | ✓ | App functionality |

## 앱 액세스 (App access) — 심사용 계정
전 앱이 로그인 필수 → «All or some functionality is restricted» 를 고르고 **심사용 계정**을 적어야 한다.
운영에 심사 전용 계정(비 superadmin, 데이터가 있는 시험 매장)이 **아직 없다** → README B6.

## 권한 설명 (Permissions declaration)
| 권한 | 앱 | 설명 |
|---|---|---|
| ACCESS_FINE/COARSE_LOCATION | Ventas | 재판매자가 처음 들어올 때 한 번, 주(provincia) 판별 — 포그라운드만 |
| CAMERA (mobile_scanner) | Ventas | 바코드 읽기 |
| USE_BIOMETRIC | Admin · Superadmin | 앱 잠금 해제 |
| REQUEST_INSTALL_PACKAGES | — | **Play 빌드에서 제거됨**(`-Pplay=true`). 신고 불필요 |
