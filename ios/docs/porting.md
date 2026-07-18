# 웹 → iOS 네이티브 포팅

**기준일:** 2026-07-18

## 제품 범위

| 웹 기능 | iOS 구현 |
|---|---|
| 엘리가 이메일 로그인·토큰 갱신 | URLSession + Keychain 기반 네이티브 인증 |
| 오늘 식단·최근 카페 주문 홈 | SwiftUI 홈 카드와 가로 메뉴 레일 |
| 날짜별 중·석식·품절·선호 메뉴 | 네이티브 DatePicker, List, 선호 키워드 |
| 카페 매장·카테고리·최근/인기·즐겨찾기 | TabView/NavigationStack, 가로 필터, List |
| 메뉴 옵션·수량·장바구니 | 네이티브 Picker, Stepper, swipe 삭제 |
| 바로 주문 장바구니 격리 | 기존 장바구니 스냅샷 후 단일 상품 검증 및 복원 |
| 결제 사유·최종 확인·주문 | Form + confirmationDialog |
| 최근 3개월 주문 내역 | 네이티브 주문 내역 List |
| 식사 알림·로그아웃 | UserNotifications + Settings Form |

## 기술 결정

- UI: SwiftUI, iOS 18+
- 상태: Observation (`@Observable`)과 좁은 `@State`/`@Binding`
- 내비게이션: 5개 독립 `NavigationStack`을 가진 `TabView`
- 네트워크: 외부 의존성 없는 URLSession, `base`/`svc` 직접 HTTPS 통신
- 보안: access/refresh token은 Keychain, 비밀번호는 저장하지 않음
- 설정: UserDefaults에는 비민감 정보만 저장
- 접근성: 시스템 텍스트 스타일, 의미 기반 색상, 44pt 탭 영역, 명시적 레이블
- 테스트: API 매핑/주문 금액/영업시간 단위 테스트와 로그인 화면 접근성 UI 테스트
- 최신 UI: iOS 26 Liquid Glass, 스크롤 시 축소되는 탭 바, 시스템 검색 역할과 Glass 버튼
- 시스템 통합: App Intents/App Shortcuts, `neweligaorder://` 딥링크, 탭 상태 복원
- 운영 품질: Network 프레임워크 연결 감시, Privacy Manifest, 취소 가능한 비동기 로딩

iOS 18–25 또는 ‘투명도 줄이기’가 활성화된 환경에서는 Liquid Glass 표면을 시스템 Material로 자동 대체합니다.

## 구조

```text
NewEligaOrder/
  App/          앱 진입점, 탭/라우팅
  Models/       API 및 화면 도메인 모델
  Networking/   인증, API 호출, 응답 매핑
  Persistence/  Keychain, 사용자 설정, 알림
  Stores/       앱 전역 인증·매장·장바구니 상태
  Features/     Auth, Home, Dining, Cafe, Cart, Orders, Settings
  Shared/       재사용 UI와 포맷터
```

## 운영상 주의

- 카페 주문은 매장 영업 계획과 서버 응답을 함께 확인합니다.
- 식당(shop 7)은 조회 전용이며 장바구니/주문 대상에서 제외합니다.
- 바로 주문은 기존 카트를 비운 뒤 단일 상품만 남았는지 검증합니다. 확인 화면을 이탈하면 기존 카트를 복원합니다.
- 서버 원본 응답의 다국어 `name` 객체는 한국어 → 영어 순으로 정규화합니다.
