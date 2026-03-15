# TutorHub 기출문항 DB 연동

PharNote는 TutorHub의 `public.past_questions`를 read-only source of truth로 사용합니다. exact lookup은 TutorHub 백엔드 API를, text search는 Supabase read-only REST를 사용합니다. 로컬 DB 복제나 별도 동기화는 하지 않습니다.

## 설정

1. TutorHub exact lookup API base URL과 Supabase anon key / project URL을 준비합니다.
2. 아래 이름으로 값을 관리합니다.
   - `PAST_QUESTIONS_API_BASE_URL`
   - `PAST_QUESTIONS_SUPABASE_URL`
   - `PAST_QUESTIONS_SUPABASE_ANON_KEY`
3. 상용 앱 빌드에서는 target build setting 또는 xcconfig로 두 값을 주입합니다.
   - 앱은 `Info.plist` 경유로 값을 읽기 때문에 사용자 화면에 연결 설정 UI가 노출되지 않습니다.
4. 개발 중에는 아래 둘 중 하나를 사용합니다.
   - Xcode `Product > Scheme > Edit Scheme > Run > Arguments`에서 환경변수 추가
   - 앱 홈의 내부 도구 `TutorHub 기출 DB`에서 URL / anon key 저장
5. iOS 앱은 `.env`를 자동 로드하지 않습니다.

## 동작

- exact lookup
  - 경로: `POST /api/pharnode/item/lookup`
  - 입력: `subject`, `year`, `month`, `questionNumber`, `examVariant`, optional `requireImage`, `requirePaperSection`, `requirePoints`
  - 기본 앱 동작: `requireImage = true`
  - 공통형 요청은 `requirePaperSection = 공통`을 같이 보냅니다.
  - 응답은 정규화된 `examVariant`, `paperSection`, `points`, `hasImage`, `imageUrl`을 포함합니다.
- search
  - 경로: Supabase `rest/v1/past_questions`
  - 대상: `content`, `answer`, `solution`, `metadata.keywords`, `metadata.unit`
  - 결과: `topK` 기준으로 snippet과 함께 반환
- 이미지
  - `image_url`은 화면 렌더링과 multimodal image input 재사용을 같이 염두에 두고 그대로 유지합니다.

## UI 진입점

- 앱 홈 > `TutorHub 기출 DB`
- DEBUG 빌드에서만 내부 도구가 보입니다. 숨기려면 `PHARNOTE_HIDE_INTERNAL_TOOLS=1`

## 수동 검증

1. exact lookup 프리셋에서 `2026 / 9 / 수학 / 22 / 공통`으로 조회
2. 검색어를 입력하고 `topK`를 조절해 관련 기출이 반환되는지 확인
3. 결과 카드에서 `image_url`이 실제로 렌더링되는지 확인
