# 엘리가오더 iOS

기존 `web/`의 주문 흐름을 SwiftUI로 포팅한 iOS 네이티브 앱입니다.

## 요구 사항

- Xcode 26 이상
- iOS 18 이상

## 실행

```bash
open NewEligaOrder.xcodeproj
```

저장소에 공유 Xcode 프로젝트와 스킴이 포함되어 있어 별도의 생성 도구가 필요하지 않습니다. `project.yml`은 XcodeGen을 사용하는 환경에서 프로젝트를 다시 생성할 때 사용할 수 있는 선택 사항입니다.

CLI 빌드:

```bash
xcodebuild build \
  -project NewEligaOrder.xcodeproj \
  -scheme NewEligaOrder \
  -destination 'platform=iOS Simulator,name=<설치된 iPhone 시뮬레이터>'
```

엘리가 계정의 access/refresh token은 Keychain에 저장합니다. 사용자 ID, 마지막 매장, 즐겨찾기와 알림 설정만 UserDefaults에 저장합니다.

## 위젯

앱을 한 번 열어 로그인하면 App Group 캐시가 갱신되고 다음 위젯을 추가할 수 있습니다.

- **지금 식단**: 현재 또는 다음 식사 시간에 맞는 메뉴
- **카페 최근 주문**: 최근 주문한 메뉴로 바로 이동
- **즐겨찾기 바로 주문**: 즐겨찾기를 고르고 안전한 주문 확인 단계로 이동

위젯과 앱은 `group.com.leeari95.NewEligaOrder` App Group으로 토큰이 아닌 표시용 스냅샷만 공유합니다.

구현 범위와 구조는 [docs/porting.md](docs/porting.md)를 참고하세요.
