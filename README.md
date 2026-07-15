# new 엘리가오더

카카오 사내 엘리가오더 API를 쓰는 반응형 웹앱입니다. 모바일·데스크톱에서 식당 식단 조회와 카페 주문 흐름을 빠르게 처리하는 데 초점을 둡니다.

## 배포 URL

https://lift.onkakao.net/share/new-eliga-order/

## 기능

- 로그인 (Bearer 토큰, 세션 스토리지)
- 매장 목록 (식당 / 카페)
- 식당(shopId 7) 날짜별 식단 조회 (주문 불가)
- 카페 카테고리·메뉴·옵션 상세
- 장바구니 추가 / 수량 변경 / 삭제
- 결제 사유 선택 + **명시적 주문 확인** 후 주문
- 주문 내역 / 최근·인기 / 상태 조회

## 기술 스택

- Vite + React + TypeScript
- React Router (SPA)
- Vitest (도메인 로직 단위 테스트)
- LIFT 정적 배포 (`base: /share/new-eliga-order/`)

## 로컬 실행

```bash
npm install
npm run dev      # Vite proxy로 CORS 우회
npm test
npm run build
npm run preview  # http://127.0.0.1:4173/share/new-eliga-order/
```

개발 서버는 `base.eligaorder.com` / `svc.eligaorder.com` 을 `/__eliga-base`, `/__eliga-svc` 로 프록시합니다.

## API

스킬 `eliga-order` 의 계약과 동일합니다.

| 용도 | 호스트 / 경로 |
|------|----------------|
| space | `GET https://base.eligaorder.com/space?brandCode=kakao` |
| 서비스 | `https://svc.eligaorder.com/{space}/...` |
| 로그인 | `POST /customer/sign-in` |
| 매장 | `GET /shop/me` |
| 식단 | `GET /meal/operation-times-and-courses` |
| 카페 메뉴 | `GET /goods/category`, `/goods/display` |
| 장바구니 | `GET/POST /goods/cart`, `PUT /goods/cart/quantity`, `DELETE /goods/cart/item` |
| 결제 사유 | `GET /payment/reason` |
| 주문 | `POST /goods/order` |

주문 본문은 `eliga-api.sh` 형태(`deviceType`, `orderType`, `payType`, `cartId`, `paymentReasonId`, `orderItems` …)를 따릅니다.

## CORS 안내

LIFT 오리진(`lift.onkakao.net`)에서 Eliga API를 직접 호출하면 CORS에 막힐 수 있습니다. 로컬 개발은 프록시를 사용하세요. 클라이언트 계약과 페이로드는 실 API와 맞춰 두었습니다.

## SPA 딥링크 (LIFT)

LIFT는 `200.html` 경로 rewrite가 동작하지 않을 수 있어, 빌드 시 주요 라우트 디렉터리에 `index.html` 셸을 복사합니다 (`vite` plugin `spa-route-shells`). 메뉴 상세는 `/cafe/:shopId/menu?d=<displayId>` 형태입니다.

## 재배포

```bash
npm run build
lift upload ./dist --name new-eliga-order --spa --expires never --force --json
```
