# Pharnote Analysis Contract

## 1. Purpose
Define the contract between `pharnote` and `pharnode` so page-level study activity can be analyzed consistently.

## 2. Principles
1. The contract must be explicit and versioned.
2. Bundles must be valid without server-only assumptions.
3. Sensitive content must be scoped to what the user selected for analysis.
4. Partial bundles are allowed if source materials are missing.
5. Pharnote must be able to queue bundles offline.

## 3. Analysis Scopes
### `page`
Current page only.

### `selection`
Current selection or region only.

### `session`
Recent activity window across one or more pages.

### `document-segment`
A bounded range of adjacent pages.

## 4. Input Bundle Schema
```json
{
  "bundleVersion": 1,
  "bundleId": "uuid",
  "createdAt": "ISO-8601",
  "sourceApp": "pharnote",
  "scope": "page|selection|session|document-segment",
  "document": {
    "documentId": "uuid",
    "documentType": "blankNote|pdf",
    "title": "string",
    "subject": "string|null",
    "collectionId": "string|null",
    "sourceFingerprint": "string|null"
  },
  "page": {
    "pageId": "uuid",
    "pageIndex": 0,
    "pageCount": 1,
    "selectionRect": null,
    "template": "blank|grid|lined|cornell|problem|null",
    "pageState": ["bookmarked", "review_due"]
  },
  "content": {
    "previewImageRef": "string|null",
    "drawingRef": "string|null",
    "drawingStats": {
      "strokeCount": 0,
      "inkLengthEstimate": 0,
      "eraseRatio": 0.0,
      "highlightCoverage": 0.0
    },
    "typedBlocks": [],
    "pdfTextBlocks": [],
    "ocrTextBlocks": [],
    "manualTags": [],
    "bookmarks": []
  },
  "behavior": {
    "sessionId": "uuid|null",
    "studyIntent": "lecture|problem_solving|summary|review|exam_prep|unknown",
    "dwellMs": 0,
    "foregroundEditsMs": 0,
    "revisitCount": 0,
    "toolUsage": [],
    "lassoActions": 0,
    "copyActions": 0,
    "pasteActions": 0,
    "undoCount": 0,
    "redoCount": 0,
    "zoomEventCount": 0,
    "navigationPath": []
  },
  "context": {
    "previousPageIds": [],
    "nextPageIds": [],
    "previousAnalysisIds": [],
    "examDate": null,
    "locale": "ko-KR",
    "timezone": "Asia/Seoul"
  },
  "privacy": {
    "containsPdfText": true,
    "containsHandwriting": true,
    "userInitiated": true
  }
}
```

## 5. Output Result Schema
```json
{
  "resultVersion": 1,
  "analysisId": "uuid",
  "bundleId": "uuid",
  "status": "completed|partial|failed",
  "completedAt": "ISO-8601",
  "summary": {
    "oneLiner": "string",
    "studyType": "concept_review|problem_solving|mixed|uncertain"
  },
  "conceptNodes": [
    {
      "nodeId": "string",
      "label": "string",
      "mastery": 0.0,
      "confidence": 0.0,
      "evidenceStrength": 0.0
    }
  ],
  "misconceptionCandidates": [
    {
      "code": "string",
      "label": "string",
      "confidence": 0.0,
      "note": "string"
    }
  ],
  "difficultyEstimate": 0.0,
  "signals": {
    "hesitation": 0.0,
    "revisionIntensity": 0.0,
    "completionConfidence": 0.0
  },
  "recommendedActions": [
    {
      "kind": "restudy|retry|practice|summarize|link-node|review-later",
      "label": "string",
      "targetNodeId": "string|null",
      "priority": 0
    }
  ],
  "review": {
    "reviewDueAt": "ISO-8601|null",
    "urgency": "low|medium|high"
  },
  "debug": {
    "warnings": [],
    "missingInputs": []
  }
}
```

## 6. Local Persistence Requirements
Pharnote should persist:
1. request metadata,
2. request payload manifest,
3. queue state,
4. response payload,
5. user actions on the result.

## 7. UI Mapping Requirements
### Input side
The Analyze sheet must show:
1. selected scope,
2. included assets,
3. study intent,
4. queue or network status.

### Output side
The Insight surface must map:
1. `conceptNodes` -> concept chips / graph entry points,
2. `mastery` -> progress indicator,
3. `misconceptionCandidates` -> warning cards,
4. `recommendedActions` -> actionable buttons,
5. `review.reviewDueAt` -> review scheduling UI.

## 8. Failure Handling
If analysis fails:
1. preserve the bundle locally,
2. allow retry,
3. show whether failure was network, authentication, validation, or server-side,
4. never lose the original page state.

## 9. Versioning Rules
1. Increment `bundleVersion` on incompatible request changes.
2. Increment `resultVersion` on incompatible response changes.
3. Older results must remain renderable at reduced fidelity.
