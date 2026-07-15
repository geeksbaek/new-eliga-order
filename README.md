# new 엘리가오더

카카오 사내 엘리가오더 API를 쓰는 반응형 웹앱입니다.

## 중요: 로그인 방식

엘리가 공식 인증은 **JSON Bearer가 아니라 HttpOnly `AccessToken` 쿠키**입니다  
(`eliga-api.sh` 와 동일). 브라우저에서 동작하려면 **같은 출처 API 프록시**가 필요합니다.

| 실행 방법 | 로그인 |
|-----------|--------|
| `npm run dev` | 동작 (Vite 프록시) |
| `npm run build && npm start` | 동작 (`server.mjs` 프록시) |
| GitHub Pages 정적 단독 | **불가** (3rd-party 쿠키/프록시 없음) |

## 실행

```bash
npm install

# 개발
npm run dev
# → http://127.0.0.1:5173/

# 프로덕션 로컬
npm run build
npm start
# → http://127.0.0.1:3456/
```

사내 엘리가 이메일/비밀번호로 로그인하세요.

## 기능

- 로그인 (쿠키 세션 + 프록시가 주입한 토큰)
- 매장 / 식당 식단(조회만) / 카페 메뉴·옵션
- 장바구니 · 결제 사유 · 주문 확인 · 주문 내역

## API

스킬 `eliga-order` 계약과 동일. 브라우저는 `/__eliga-base`, `/__eliga-svc` 로 호출하고,  
개발 서버·`server.mjs` 가 `base.eligaorder.com` / `svc.eligaorder.com` 으로 넘깁니다.
