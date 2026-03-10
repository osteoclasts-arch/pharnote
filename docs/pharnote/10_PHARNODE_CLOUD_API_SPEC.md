# pharnode Supabase Sync Spec v1

## 목적
`pharnote`에서 생성한 분석 번들, 복습 큐 요약, 대시보드 스냅샷을 실제 운영 `pharnode` Supabase backend로 안정적으로 전송하기 위한 Edge Function 계약.

## 인증
- Header: `Authorization: Bearer <token>`
- token은 `pharnode`와 같은 Supabase project의 user access token
- 모든 write endpoint는 idempotent 하게 처리
- 같은 `bundleId` 또는 같은 snapshot dedupe key는 중복 생성 금지

## Base URL
- 운영 project URL: `https://djxxqvglkqqpkmbudksr.supabase.co`
- Edge Functions prefix: `/functions/v1`

## Endpoints

### POST `/functions/v1/pharnote-register-bundle`
분석 번들 업로드.

Request body:
```json
{
  "bundle": {"bundleId": "uuid", "bundleVersion": 1},
  "result": {"analysisId": "uuid"},
  "assets": {
    "previewImageBase64": "optional",
    "drawingDataBase64": "optional"
  },
  "client": {
    "sourceApp": "pharnote",
    "appVersion": "1.0",
    "platform": "iPadOS",
    "locale": "ko_KR",
    "timezone": "Asia/Seoul"
  }
}
```

Success response:
```json
{
  "status": "accepted",
  "jobId": "uuid",
  "acceptedAt": "2026-03-09T00:00:00Z"
}
```

### POST `/functions/v1/pharnote-sync-dashboard`
교재 진도 및 복습 큐 스냅샷 업로드.

Request body:
```json
{
  "snapshot": {"version": 1, "generatedAt": "..."},
  "reviewTasks": [],
  "client": {
    "sourceApp": "pharnote",
    "appVersion": "1.0",
    "platform": "iPadOS",
    "locale": "ko_KR",
    "timezone": "Asia/Seoul"
  }
}
```

Success response:
```json
{
  "status": "accepted",
  "acceptedAt": "2026-03-09T00:00:00Z"
}
```

### GET `/functions/v1/pharnote-bundle-status?bundleId=<uuid>`
등록된 bundle 상태와 최신 result 조회.

## 서버 요구사항
1. `bundleId` 기준 idempotency 보장
2. payload schema validation 필수
3. 업로드 원문과 정규화 데이터 분리 저장
4. asset base64가 오면 `pharnote-assets` storage bucket에 저장
5. 4xx/5xx 응답 body에 사람이 읽을 수 있는 message 포함
6. RLS 기준은 `user_id = auth.uid()`

## 클라이언트 요구사항
1. 로컬 outbox 선적재 후 비동기 전송
2. 실패 시 재시도
3. 이미 성공한 bundle은 재부팅 후 재전송 금지
4. dashboard snapshot은 최신 1개 dedupe key로 overwrite 가능
5. 설정 화면에서는 `Supabase project URL`과 `Supabase access token`을 다룸
