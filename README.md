# new 엘리가오더

카카오 사내 엘리가오더 API를 쓰는 반응형 웹앱입니다. 모바일·데스크톱에서 식당 식단 조회와 카페 주문 흐름을 빠르게 처리하는 데 초점을 둡니다.

## 사용 URL

https://geeksbaek.github.io/new-eliga-order/

(GitHub Pages — Eliga API 직접 호출, CSP 제한 없음)

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
- GitHub Pages (`base: /new-eliga-order/`)

## 로컬 실행

```bash
npm install
npm run dev      # Vite proxy로 API 프록시
npm test
npm run build:pages
npm run preview  # base 경로 확인 시 사용
```

개발 서버는 `base.eligaorder.com` / `svc.eligaorder.com` 을 `/__eliga-base`, `/__eliga-svc` 로 프록시합니다.  
프로덕션(GitHub Pages)은 API를 브라우저에서 직접 호출합니다(Eliga CORS가 Origin을 반영).

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

## 재배포 (GitHub Pages)

```bash
npm run build:pages
# dist/ 내용을 gh-pages 브랜치로 푸시
rm -rf /tmp/new-eliga-pages && mkdir -p /tmp/new-eliga-pages
cp -R dist/. /tmp/new-eliga-pages/
cd /tmp/new-eliga-pages
git init && git checkout -b gh-pages
git add -A && git commit -m "deploy"
git remote add origin https://github.com/geeksbaek/new-eliga-order.git
git push -f origin gh-pages
```
