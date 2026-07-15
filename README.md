# 엘리가오더

[엘리가 오더](https://webapp.eligaorder.com) API를 쓰는 사내 식당·카페 SPA입니다.  
모바일 웹/PWA 기준으로 메뉴 조회, 카페 주문, 식단 확인을 한 화면에서 처리합니다.

**라이브:** https://new-eliga.vercel.app/  
**저장소:** https://github.com/geeksbaek/new-eliga-order

## 기능

- **홈** — 오늘 식단(추천 반찬 하이라이트), 최근 카페 주문
- **식단** — 날짜별 중·석식, 품절 필터, 선호 음식(반찬 칩) 설정
- **카페** — 매장 pill, 카테고리, 즐겨찾기, 운영시간 게이트, 장바구니·주문
- **주문 내역** — 계정 주문 히스토리
- **설정** — 식사 알림 등
- **PWA** — 홈 화면 추가, 매니페스트·아이콘·서비스 워커

로그인 계정은 엘리가 오더(사내) 이메일/비밀번호입니다. 사내·외부망 모두 사용 가능합니다.

## 기술 스택

| 구분 | 내용 |
|------|------|
| 프론트 | React 19, TypeScript 7 (`tsc`) + 6 API (Vercel/eslint 호환), Vite 8, React Router 7 |
| 배포 | Vercel (`icn1`), SPA rewrites |
| API | 엘리가 `base` / `svc` — 동일 출처 프록시 `/api/proxy` |
| 이미지 | NCloud CDN + 색 샘플용 `/api/cdn` |
| 테스트 | Vitest |

## 로컬 실행

```bash
npm install
npm run dev          # http://127.0.0.1:5173  (Vite + 프록시 미들웨어)
```

빌드 후 Node 서버:

```bash
npm run build
npm start            # http://127.0.0.1:3456  (server.mjs)
```

```bash
npm test             # 단위 테스트
```

환경 변수(선택):

| 변수 | 설명 |
|------|------|
| `VITE_USE_PROXY` | `false`면 브라우저가 엘리가 호스트에 직접 요청(CORS 이슈 가능). 기본은 프록시 사용 |
| `VITE_BASE` | 배포 base path. 프로덕션 빌드는 `/` |

## 배포

GitHub Actions가 **push마다** Vercel에 배포합니다.

| 이벤트 | 대상 |
|--------|------|
| `main` 푸시 | Production (`https://new-eliga.vercel.app`) |
| 그 외 브랜치 / PR | Preview URL (PR 코멘트로 남김) |
| Actions → Deploy Vercel → Run workflow | 수동 배포 |

워크플로: [`.github/workflows/deploy-vercel.yml`](.github/workflows/deploy-vercel.yml)  
순서: `npm test` → `vercel pull` → `vercel build` → `vercel deploy --prebuilt`

저장소 Secrets:

| Secret | 설명 |
|--------|------|
| `VERCEL_TOKEN` | [Account Tokens](https://vercel.com/account/tokens)에서 만든 **Access Token** (`vcp_…`). CLI 로그인 세션 토큰(`vca_…`)은 만료되므로 쓰지 말 것 |
| `VERCEL_ORG_ID` | 팀/ORG ID (`.vercel/project.json`의 `orgId`) |
| `VERCEL_PROJECT_ID` | 프로젝트 ID (`.vercel/project.json`의 `projectId`) |

로컬에서 수동 배포할 때:

```bash
vercel login              # 최초 1회
vercel deploy --prod -y
```

`vercel.json`에서 SPA fallback, CSP·보안 헤더, 리전 `icn1`을 지정합니다.  
빌드 시 주요 경로용 HTML 셸을 생성합니다(`scripts/assert-spa-shells.mjs`).

## 디렉터리

```
api/
  proxy.ts          # 엘리가 API 프록시 (쿠키 first-party, 로그인 JWT 주입)
  cdn.ts            # 메뉴 이미지 프록시 (캔버스 색 샘플용)
docs/
  gemma4-browser-llm.md  # Gemma 4 브라우저(온디바이스) LLM 조사
src/
  api/              # HTTP 클라이언트, 엘리가 엔드포인트 래퍼
  pages/            # 라우트 페이지
  components/       # 공통 UI
  hooks/            # auth, shop/cart, mutations
  lib/              # 매퍼, 캐시, 식단/카페 규칙, 선호 음식 등
public/
  manifest.webmanifest
  sw.js
  icon-*.png
server.mjs          # 로컬/도커용 정적 + 프록시 서버
vercel.json
```

## 관련 조사

- [Gemma 4 브라우저 임베딩](docs/gemma4-browser-llm.md) — E2B/E4B 웹 전용 패키지(`*-web.litertlm`), LiteRT-LM, new-eliga 적용 시 제약

## 인증

1. `POST …/customer/sign-in` — access/refresh 토큰(또는 쿠키 세션)
2. 토큰은 `localStorage`에 보관해 탭을 닫아도 유지
3. access 만료 임박 시 refresh, 요청 401 시 1회 refresh 후 재시도
4. 프록시는 upstream `Set-Cookie`를 동일 출처·`HttpOnly`/`Secure`/`SameSite=Lax`로 재작성

프록시가 필요한 이유: 엘리가 쿠키를 브라우저 first-party로 다루고, CORS 없이 SPA에서 호출하기 위함입니다.

## 주요 라우트

| 경로 | 설명 |
|------|------|
| `/` | 홈 |
| `/login` | 로그인 |
| `/dining/:shopId` | 식단 (기본 shop 7) |
| `/cafe/:shopId` | 카페 메뉴 (`favorites` = 즐겨찾기 뷰) |
| `/cafe/:shopId/menu?d=` | 메뉴 상세 |
| `/cart` | 장바구니 |
| `/order/confirm` | 주문 확인 |
| `/orders` | 주문 내역 |
| `/settings` | 설정 |

## 카페 매장 (고정)

| shopId | 이름 |
|--------|------|
| 3 | 춘식도락 with in the box (4F) |
| 4 | kafé 3F |
| 5 | kafé 5F (기본) |
| 8 | kafé 5F b |
| 7 | 춘식도락 B1F (식단 전용, 주문 불가) |

운영시간은 `/sales-plan/cafe/{shopId}` 기준으로 클라이언트에서 주문 가능 여부를 막습니다.

## 개발 메모

- **캐시:** 메뉴·장바구니·식단 카탈로그 등은 메모리/localStorage TTL
- **선호 음식:** 과거 식단 `information`의 `[원산지]` 줄에서 반찬을 뽑아 칩으로 선택
- **PWA:** `manifest.webmanifest` + `sw.js` (API는 캐시하지 않음)
- **보안:** 프록시 path/host 검증, CDN 이미지 타입·크기 제한, CSP 및 기본 보안 헤더

## 라이선스

Private / 사내 이용 목적. 엘리가 오더 API·매장 데이터 권한은 본인 계정에 따릅니다.
