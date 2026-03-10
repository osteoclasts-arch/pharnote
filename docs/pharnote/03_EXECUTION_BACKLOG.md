# Pharnote Execution Backlog

## Delivery Rule
Every step must remain buildable and user-visible.

## Phase 0: Product Grounding
### Goal
Freeze product direction before broad implementation.

### Deliverables
1. master execution prompt,
2. product spec,
3. analysis contract,
4. implementation backlog.

### Exit criteria
- product identity is unambiguous,
- pharnote/pharnode relationship is defined,
- the first coding phase can start without strategic ambiguity.

## Phase 1: Brand and Design System Reset
### Goal
Make the app visually feel like a premium first-party product instead of a prototype.

### Tasks
1. normalize naming and display strings to `pharnote` consistently,
2. replace current theme tokens with a stronger visual system,
3. define color, spacing, radius, shadow, motion, and typography tokens,
4. design floating panel, toolbar button, pill segment, tag, and badge components,
5. redesign Library as a study desk home screen,
6. add empty/loading/error states that feel branded.

### Code areas
- `pharnote/DesignSystem/*`
- `pharnote/Views/LibraryView.swift`
- `pharnote/Views/ContentView.swift`
- project display strings where needed.

### Exit criteria
- opening the app immediately feels branded,
- the library has hierarchy and emotional appeal,
- UI components look consistent.

## Phase 2: Handwriting Workspace Polish
### Goal
Make blank-note writing feel premium and uninterrupted.

### Tasks
1. replace generic top-right toolbar emphasis with a custom study tool dock,
2. redesign pen / highlighter / eraser / lasso presentation,
3. improve page strip selection feedback,
4. add page status badges and quick bookmark/analyze entry,
5. separate writing HUD from navigation chrome,
6. ensure autosave and undo/redo feel stable.

### Code areas
- `pharnote/Views/BlankNoteEditorView.swift`
- `pharnote/Views/PencilCanvasView.swift`
- `pharnote/ViewModels/BlankNoteEditorViewModel.swift`
- `pharnote/DesignSystem/*`

### Exit criteria
- the workspace has a distinct custom identity,
- tool switching is fast and attractive,
- page actions are clearer than the current prototype.

## Phase 3: PDF Workspace Polish
### Goal
Make PDF study the strongest workflow in the app.

### Tasks
1. redesign PDF lower panel into a more intentional workspace control surface,
2. improve page jump and text search affordances,
3. add bookmark and page-state markers,
4. make lasso actions feel integrated rather than appended,
5. visually separate document content from tool chrome,
6. refine finger scroll versus pencil write behavior.

### Code areas
- `pharnote/Views/PDFDocumentEditorView.swift`
- `pharnote/Views/PDFKitView.swift`
- `pharnote/ViewModels/PDFEditorViewModel.swift`

### Exit criteria
- solving on a PDF feels like a first-class path,
- page navigation and search are fast,
- the workspace communicates study structure.

## Phase 4: GoodNotes-Class Core Parity
### Goal
Close the biggest functional gaps against premium note/PDF apps before expanding the intelligence layer.

### Tasks
1. strengthen pen, highlighter, eraser, lasso, and shape workflows,
2. improve page management and thumbnail behavior,
3. improve document organization, rename, duplicate, and move flows,
4. stabilize PDF import, section mapping, and page navigation,
5. reduce visible admin/debug surfaces in release UX,
6. harden autosave, recovery, and background persistence.

### Exit criteria
- the app stands on its own as a premium note/PDF tool,
- users can keep working even if they ignore pharnode features.

## Phase 5: Study Signal Instrumentation
### Goal
Capture enough local evidence to support meaningful analysis.

### Tasks
1. define `StudySession`, `PageStudyEvent`, and `AnalysisRequest` models,
2. record page entry/exit, dwell time, revisit count, tool usage, and major edits,
3. store page-level metadata alongside drawings,
4. add lightweight app catalog persistence for events and request queue,
5. keep instrumentation off the critical drawing path.

### Code areas
- `pharnote/Models/*`
- `pharnote/Services/*`
- `pharnote/ViewModels/*`

### Exit criteria
- current page/session behavior is persistable,
- no visible performance regression.

## Phase 6: Analyze Action v1
### Goal
Introduce page-level analysis as a first-class workflow.

### Tasks
1. add Analyze button in blank note and PDF workspaces,
2. add Analyze sheet with scope and study-intent controls,
3. build local `AnalysisBundle` generation,
4. persist queued analysis requests,
5. add temporary local debug rendering for generated bundles.

### Exit criteria
- the user can explicitly prepare a valid analysis package,
- bundle generation is inspectable and retryable.

## Phase 7: Pharnode Result Rendering
### Goal
Render pharnode output directly in pharnote.

### Tasks
1. define `AnalysisResult` model,
2. show concept chips, mastery, confidence, and recommendations,
3. add page analysis state badges,
4. support retry and stale-result handling,
5. allow jump-to-pharnode for deep graph exploration.

### Exit criteria
- pharnote becomes visibly smarter after analysis,
- insights are actionable rather than decorative.

## Phase 8: Meta-Cognition Surfaces
### Goal
Help users interpret their own work without turning pharnote into a direct tutoring workflow.

### Tasks
1. improve page insight wording and evidence presentation,
2. surface recent insights, document progress, and work patterns in Home,
3. separate passive evidence capture from explicit analysis actions,
4. support jump-to-pharnode for deeper interpretation and dashboards.

### Exit criteria
- users understand what the app captured and why it matters,
- the app supports reflection without overwhelming the writing workflow.

## Phase 9: Hardening
### Goal
Raise the app from impressive prototype to dependable product.

### Tasks
1. package integrity checks,
2. crash recovery and autosave validation,
3. scaling tests for large PDFs and multi-page notes,
4. thumbnail and cache pressure controls,
5. search and indexing optimization,
6. accessibility, pointer, and input polish.

### Exit criteria
- stable repeated sessions,
- predictable recovery,
- no major performance cliffs.

## Immediate Next Implementation Step
Start with Phase 1.

### Recommended first coding slice
1. redesign the design tokens,
2. rebuild `LibraryView` into a branded study home,
3. normalize visible app naming to `pharnote` where currently inconsistent.

### Why this is first
- it creates a visible product identity quickly,
- it does not block later architecture,
- it establishes the UI language future work must follow.
