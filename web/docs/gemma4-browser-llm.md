# Gemma 4 브라우저 임베딩 조사

조사일: 2026-07-16  
목적: new-eliga SPA에 온디바이스(브라우저) LLM을 붙일 때 쓸 수 있는 Gemma 4 모델·런타임 정리

---

## 요약

Gemma 4 패밀리 안에 **모바일·엣지·브라우저 배포를 전제로 설계된 소형 라인**이 있다.

| 구분 | 모델 | 비고 |
|------|------|------|
| 엣지용 기본 라인 | **Gemma 4 E2B**, **Gemma 4 E4B** | E = effective parameters. 초소형·온디바이스·브라우저 타깃 |
| 웹 전용 패키지 | `gemma-4-E2B-it-web.litertlm` / `gemma-4-E4B-it-web.litertlm` | 브라우저 메모리 제약을 위해 **별도 최적화**. 현재 **text-only** |
| 권장 런타임 | **LiteRT-LM** (`@litert-lm/core`, WebGPU) | 프로덕션 경로. MediaPipe LLM Inference 웹 경로는 maintenance mode |

“브라우저에 임베딩하려고 튜닝한 모델”에 가장 가깝게 대응하는 것은  
`litert-community` 가 배포하는 **`*-it-web.litertlm`** 파일이다. 베이스 가중치는 E2B/E4B instruction 모델이고, 웹 런타임·메모리 제약에 맞게 양자화·패키징한 변형이다.

---

## Gemma 4 패밀리에서 엣지/웹 위치

공식 개요([Gemma 4 model overview](https://ai.google.dev/gemma/docs/core)) 기준 크기 라인:

| 라인 | 역할 |
|------|------|
| **E2B / E4B** | ultra-mobile, edge, **browser** (Pixel, Chrome 등) |
| 12B | 노트북·로컬 에이전트, multimodal |
| 26B A4B (MoE) / 31B | 고성능 로컬·워크스테이션 |

E2B·E4B 아키텍처 특징:

- **PLE (Per-Layer Embeddings)**: 레이어별 임베딩 테이블로 effective parameter 효율을 올림. 테이블은 조회 위주라 런타임이 메모리 매핑 등으로 상주 메모리를 줄일 수 있음
- 작은 모델 컨텍스트: 문서상 **128K** 급 (LiteRT-LM 벤치마크 카드는 기본 측정 2K, 지원 상한 32K 표기)
- 멀티모달(텍스트·이미지·오디오)은 네이티브 모델에 있으나, **웹 전용 패키지는 현재 text-only**
- **Multi-Token Prediction (MTP)** draft 모델 포함 → speculative decoding 가속
- 라이선스: **Apache 2.0**

대략 메모리 가이드(가중치 로드 기준, 오버헤드·KV 캐시 제외, 공식 표):

| 모델 | BF16 | Q4_0 | Mobile | Mobile (text-only) |
|------|------|------|--------|--------------------|
| E2B | 11.4 GB | 2.9 GB | 1.1 GB | **0.84 GB** |
| E4B | 17.9 GB | 4.5 GB | 2.5 GB | **2.2 GB** |

모바일/엣지 배포에는 QAT(Quantization-Aware Training) 및 LiteRT-LM용 mixed bit(2/4/8-bit) 스킴이 별도로 제공된다. 일반 PTQ보다 품질 저하를 줄인 경로.

---

## “웹 전용으로 튜닝·패키징된” 산출물

### Hugging Face (LiteRT Community)

| 저장소 | 웹 파일 | 디스크 크기(웹) | 일반 패키지 크기 |
|--------|---------|-----------------|------------------|
| [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) | `gemma-4-E2B-it-web.litertlm` | **~2.0 GB** (2008 MB) | ~2.58 GB |
| [litert-community/gemma-4-E4B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm) | `gemma-4-E4B-it-web.litertlm` | **~3.0 GB** (2969 MB) | ~3.65 GB |

모델 카드 문구(요지):

> Web on LiteRT-LM uses a **specially optimized model** for Web because of its unique memory constraints. Currently the model is **text-only**.

MediaPipe 호환 파일도 같은 저장소에 있다 (`gemma-4-E2B-it-web.task`, `gemma-4-E4B-it-web.task`).  
다만 웹용 **권장 경로는 LiteRT-LM** 이고, MediaPipe LLM Inference 웹 경로는 **maintenance mode** 로 안내된다.

웹 데모 스페이스: [huggingface.co/spaces/tylermullen/Gemma4](https://huggingface.co/spaces/tylermullen/Gemma4)  
공식 채팅 데모: [google-ai-edge.github.io/LiteRT-LM/web_demos/chat](https://google-ai-edge.github.io/LiteRT-LM/web_demos/chat/index.html)

### 웹 벤치마크 (모델 카드 공시)

조건: LiteRT-LM, prefill 1024 / decode 256, context 2048, WebGPU.

| 모델 | 장치 | Prefill tok/s | Decode tok/s | TTFT | GPU 메모리 |
|------|------|---------------|--------------|------|------------|
| E2B web | MacBook Pro M4 Max | 4,853 | **73** | 1.09 s | ~1.8 GB |
| E4B web | MacBook Pro M4 Max | 1,590 | **44** | 1.75 s | ~3.3 GB |

Google 개발자 블로그([Blazing fast on-device GenAI with LiteRT-LM](https://developers.googleblog.com/blazing-fast-on-device-genai-with-litert-lm/), 2026-05-19)는 Chrome + M4 Max 기준 Gemma 4 E2B decode **~76 tok/s** 급을 언급한다. 측정 설정에 따라 카드 수치와 소폭 차이 날 수 있다.

참고로 네이티브 GPU(맥 Metal) E2B decode는 **~160 tok/s** 까지 나와, 웹(WebGPU)은 네이티브 대비 느리지만 브라우저 안에서 쓸 만한 수준이다.

---

## 런타임 스택

```
앱 (React SPA)
  └─ @litert-lm/core  (JS/TS Web API, early preview)
       └─ LiteRT-LM  (KV cache, chat template, function calling, session)
            └─ LiteRT  (구 TFLite 계열 런타임)
                 └─ WebGPU (브라우저) / XNNPACK·MLDrift (네이티브)
```

### LiteRT-LM Web API (권장)

- 문서: [LiteRT-LM Web API](https://developers.google.com/edge/litert-lm/js)
- npm: `@litert-lm/core`
- 상태: **early preview**, text-in / text-out, **WebGPU 필수**
- **현재 지원 웹 모델 (공식 목록)**  
  - `gemma-4-E2B-it-web.litertlm`  
  - `gemma-4-E4B-it-web.litertlm`  
  일반 `.litertlm` 전 모델 범용 지원은 확대 예정이라고 명시

최소 사용 예 (공식 샘플 요약):

```js
import { Engine } from '@litert-lm/core'

const engine = await Engine.create({
  model:
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm',
  mainExecutorSettings: {
    maxNumTokens: 8192,
  },
})

const chat = await engine.createConversation({
  preface: {
    messages: [{ role: 'system', content: 'You are a helpful assistant' }],
  },
})

for await (const chunk of chat.sendMessageStreaming('오늘 점심 뭐 먹지?')) {
  // chunk.content[0].text
}

await engine.delete()
```

CDN 경로: `https://cdn.jsdelivr.net/npm/@litert-lm/core/+esm`

### MediaPipe LLM Inference (레거시·유지보수)

- 가이드: [Deploy Gemma in web browsers](https://ai.google.dev/gemma/docs/integrations/web), [LLM Inference Web](https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/web_js)
- `.task` 파일로 동작
- LiteRT-LM 문서/모델 카드에서 **maintenance mode** 로 표기 → 신규 통합은 LiteRT-LM 우선

### 대안 스택 (Gemma 4 웹 전용 패키지와는 별개)

| 스택 | 용도 |
|------|------|
| WebLLM / MLC | 범용 브라우저 LLM, Gemma 계열 지원 여부는 버전별로 확인 |
| transformers.js | 임베딩·소형 생성, 검색/유사도 쪽에 유리 |
| Chrome Prompt API / Gemini Nano | 설치 부담 적음, 기기·채널 제약 |

new-eliga에 “공식 Gemma 4 웹 튜닝 가중치”를 그대로 쓰려면 **LiteRT-LM + `*-web.litertlm`** 조합이 1순위다.

---

## new-eliga 적용 시 고려사항

이 앱은 모바일 웹/PWA 중심 사내 식당·카페 SPA다. 로컬 LLM 후보는 이전 아이데이션(식단 1줄 추천, 알림 문구, 시맨틱 메뉴 매칭 등)과 맞춘다.

### 모델 선택

| 후보 | 언제 |
|------|------|
| **E2B web (~2 GB)** | 기본. 한 줄 요약·구조화 JSON·짧은 추천 |
| **E4B web (~3 GB)** | 품질이 부족할 때만. 다운로드·VRAM 부담 큼 |
| 임베딩 전용 소형 모델 | “제육 ≈ 불고기” 유사 반찬 매칭은 생성 모델보다 임베딩이 안정적일 수 있음 |

### 제품/UX 제약

1. **다운로드 크기**  
   첫 방문 강제 다운로드는 부담이 크다. 설정 옵트인, Wi-Fi only, SW/Cache Storage 캐시, 진행률 UI가 필요하다.

2. **WebGPU**  
   미지원 브라우저·일부 모바일 GPU에서는 폴백(규칙 매칭·서버 없음·기능 숨김)이 필요하다.

3. **메모리**  
   웹 E2B만 GPU ~1.8 GB 급. 탭 여러 개·저사양 폰에서는 OOM 가능. 사용 후 `engine.delete()` 필수.

4. **텍스트 only**  
   메뉴 이미지 해석은 웹 패키지로 불가. 메뉴 텍스트·영양·선호 칩만 컨텍스트로 넣는다.

5. **할루시네이션**  
   가격·품절·운영시간은 API 정답을 우선하고, 모델은 추천 문구·필터 후보 정도에 제한한다.

6. **프라이버시**  
   선호·주문 이력을 기기 밖으로 안 보내는 게 로컬 경로의 이점. 모델 가중치 CDN/HF 로드와 프롬프트 텔레메트리는 분리해서 설계한다.

7. **CSP**  
   현재 Vercel CSP·보안 헤더가 있다. WASM/WebGPU, 모델 CDN, `blob:`/`wasm-unsafe-eval` 등 허용 여부가 빌드 전 점검 항목이다.

### 추천 실험 순서 (기술)

1. 설정 플래그 + WebGPU 탐지 + E2B web 로드 PoC (오프라인 페이지/데모 라우트)
2. 구조화 출력(JSON): 오늘 식단 → `{ recommend, reasons[], highlightNames[] }`
3. 알림 바디 한 줄 생성 (실패 시 기존 고정 문구)
4. (병행) 임베딩으로 선호 반찬 유사 매칭 품질 비교
5. 캐시·삭제·옵트아웃 UX

---

## 아티팩트·링크 치트시트

| 항목 | URL |
|------|-----|
| Gemma 4 개요 | https://ai.google.dev/gemma/docs/core |
| LiteRT-LM 개요 | https://developers.google.com/edge/litert-lm/overview |
| LiteRT-LM Web/JS | https://developers.google.com/edge/litert-lm/js |
| Gemma 4 on LiteRT-LM | https://developers.google.com/edge/litert-lm/models/gemma-4 |
| E2B LiteRT 카드 | https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm |
| E4B LiteRT 카드 | https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm |
| E2B web 가중치 | https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/blob/main/gemma-4-E2B-it-web.litertlm |
| E4B web 가중치 | https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/blob/main/gemma-4-E4B-it-web.litertlm |
| Web models 컬렉션 | https://huggingface.co/collections/litert-community/web-llm-models |
| 성능 블로그 (2026-05) | https://developers.googleblog.com/blazing-fast-on-device-genai-with-litert-lm/ |
| QAT 안내 | https://ai.google.dev/gemma/docs/core (QAT 섹션) / HF `gemma-4-qat-mobile` 컬렉션 |
| npm | `@litert-lm/core` |
| 소스 | https://github.com/google-ai-edge/LiteRT-LM |

---

## 결론

- “브라우저 임베딩용으로 튜닝된 Gemma 4”는 마케팅 표현에 가깝고, 실체는  
  **(1) 엣지용 E2B/E4B 아키텍처 + (2) LiteRT-LM 웹 메모리 제약용 `*-web.litertlm` 패키지** 다.
- new-eliga 관점 1순위: **`gemma-4-E2B-it-web.litertlm` + `@litert-lm/core` + WebGPU**.
- 생성 챗봇 전체보다 **짧은 구조화 추천·알림 문구**에 두고, 유사 메뉴 매칭은 임베딩 병행이 안전하다.
- 웹 패키지는 **text-only**, **early preview API**, **~2 GB 다운로드** 제약을 제품 설계에 먼저 반영해야 한다.

이 문서는 공개 문서·모델 카드 기준 스냅샷이다. API·지원 모델 목록·수치는 Google AI Edge / Hugging Face 카드를 우선한다.
