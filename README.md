# new 엘리가오더

카카오 사내 엘리가오더 API를 쓰는 반응형 웹앱입니다.

## 서비스 URL (Vercel)

**https://new-eliga.vercel.app/**

- 프론트 + 엘리가 API 프록시(`/__eliga-base`, `/__eliga-svc`) 포함
- 로그인: 사내 엘리가 이메일/비밀번호
- 인증은 쿠키 기반이라 **같은 출처 프록시**가 필요 → Vercel Serverless로 처리

## 로컬 실행

```bash
npm install
npm run dev          # http://127.0.0.1:5173/
# 또는
npm run build && npm start   # http://127.0.0.1:3456/
```

## 재배포 (Vercel)

```bash
vercel login         # 최초 1회
vercel deploy --prod --yes
```

## 구조

| 경로 | 역할 |
|------|------|
| `src/` | React SPA |
| `api/eliga-base/`, `api/eliga-svc/` | Vercel Serverless 프록시 (쿠키 first-party 변환 + 로그인 시 JWT 주입) |
| `server.mjs` | 로컬/Docker용 Node 프록시 서버 |

사내 k8s·LIFT·D2Hub 등 내부 자원은 사용하지 않습니다.
