# 뉴 엘리가 오더

엘리가 오더를 웹과 iOS 네이티브 클라이언트로 함께 관리하는 모노레포입니다.

## 디렉터리

- `web/` — 기존 React/Vite PWA와 Vercel API 프록시
- `ios/` — SwiftUI 기반 iOS 네이티브 앱

각 클라이언트의 실행 방법과 구조는 해당 디렉터리의 README를 참고하세요.

## 빠른 검증

```bash
cd web && npm test && npm run build
cd ../ios && xcodebuild test -project NewEligaOrder.xcodeproj -scheme NewEligaOrder -destination 'platform=iOS Simulator,name=<설치된 시뮬레이터>'
```
