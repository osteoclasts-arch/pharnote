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

## Approved Next Implementation Track
This track is approved for the current product state after the recent save, tab, and writing stability work.

The sequencing rule is simple:
1. prioritize features that reduce study friction in long PDF and handwriting sessions,
2. then add features that increase the amount of structured study evidence,
3. only then add review-loop surfaces that turn evidence into learning workflows.

## Sprint A: PDF Study Navigation Layer
### Goal
Make long-form PDF study feel deliberate, navigable, and safe from accidental ink.

### Tasks
1. add a workspace sidebar with `thumbnails`, `outline`, `bookmarks`, and `recordings` modes,
2. add bookmark-only filtering and a clearer bookmarked-page affordance,
3. support native PDF internal and external hyperlink navigation,
4. add an explicit `Read Only` mode that disables writing while keeping navigation, search, and audio available,
5. surface current section and progress more clearly inside the workspace.

### Code areas
- `pharnote/Views/PDFDocumentEditorView.swift`
- `pharnote/Views/PDFKitView.swift`
- `pharnote/ViewModels/PDFEditorViewModel.swift`
- `pharnote/Views/DocumentEditorView.swift`

### Exit criteria
- a long PDF can be reopened and navigated quickly,
- accidental writing during reading/review is avoidable,
- bookmarks and section context are visible enough to support return study.

### Estimate
- 1 sprint

## Sprint B: Gesture-First Ink Flow
### Goal
Reduce tool-switch friction during problem solving.

### Tasks
1. add `Scribble to Erase`,
2. add `Circle to Select`,
3. add a `Ruler` tool if the math workflow remains a primary focus,
4. improve gesture feedback so the user can tell when a stroke became erase/select intent,
5. keep gesture recognition out of the critical stroke path so writing latency stays flat.

### Code areas
- `pharnote/Views/PencilPassthroughCanvasView.swift`
- `pharnote/Views/PencilCanvasView.swift`
- `pharnote/Views/PDFKitView.swift`
- `pharnote/ViewModels/BlankNoteEditorViewModel.swift`
- `pharnote/ViewModels/PDFEditorViewModel.swift`

### Exit criteria
- common erase/select actions happen without explicit tool switching,
- the gesture layer feels additive rather than surprising,
- writing latency does not regress.

### Estimate
- 1 sprint

## Sprint C: Audio Replay
### Goal
Turn audio from a file attachment into time-linked study context.

### Tasks
1. timestamp stroke batches, page changes, and major navigation events while recording,
2. add replay mode that follows the recorded page and progressively restores stroke context,
3. show recording anchors inside the PDF sidebar and note page chrome,
4. allow jumping from a recording to the page and approximate moment it was created,
5. preserve replay metadata as local study evidence for later pharnode analysis.

### Code areas
- `pharnote/Views/DocumentEditorView.swift`
- `pharnote/Views/BlankNoteEditorView.swift`
- `pharnote/Views/PDFDocumentEditorView.swift`
- `pharnote/ViewModels/BlankNoteEditorViewModel.swift`
- `pharnote/ViewModels/PDFEditorViewModel.swift`
- `pharnote/Services/StudyEventLogger.swift`

### Exit criteria
- a recording can guide the user back through the associated page work,
- replay is meaningfully better than raw audio playback,
- replay events are captured as structured local metadata.

### Estimate
- 1 to 2 sprints

## Sprint D: Internal Link Layer
### Goal
Connect summary notes, source problems, and review pages into one study graph.

### Tasks
1. add a local model for `document link` and `page link`,
2. support inserting links from selected text, page actions, or bookmarks,
3. render tappable internal links in blank notes and PDF workspaces,
4. add lightweight backlink surfaces so related pages can be reopened quickly,
5. keep the data model compatible with future `concept node` linking in pharnode.

### Code areas
- `pharnote/Models/PharDocument.swift`
- `pharnote/Services/LibraryStore.swift`
- `pharnote/Views/BlankNoteEditorView.swift`
- `pharnote/Views/PDFDocumentEditorView.swift`
- `pharnote/ViewModels/LibraryViewModel.swift`

### Exit criteria
- users can jump between related study artifacts in one or two taps,
- linked pages feel useful for review rather than decorative,
- the feature is ready to bridge into pharnode concept mapping later.

### Estimate
- 1 sprint

## Sprint E: Study Sets and Smart Review
### Goal
Turn writing and PDF work into repeatable review loops.

### Tasks
1. generate candidate study cards from OCR text, highlights, bookmarks, and later analysis output,
2. let the user edit and confirm cards before they enter review,
3. build a due-review queue with simple spaced repetition scheduling,
4. add `jump back to source page` from every card,
5. surface due reviews on Home without turning the app into a tutoring dashboard.

### Code areas
- `pharnote/Models/StudyMaterialSupport.swift`
- `pharnote/Services/SearchInfrastructure.swift`
- `pharnote/Services/DocumentOCRService.swift`
- `pharnote/Views/LibraryView.swift`
- `pharnote/Views/ContentView.swift`
- `pharnote/Models/AnalysisModels.swift`

### Exit criteria
- the user can create cards from real study artifacts,
- reviews can be completed and resumed later,
- every review item retains a clear path back to the original note or PDF page.

### Estimate
- 2 to 3 sprints

## Explicitly Deferred
These can matter later, but they should not outrank the approved track above.

1. handwriting spellcheck,
2. full handwriting reflow or edit mode,
3. collaboration-first surfaces,
4. decorative marketplace or sticker-style feature work,
5. broad AI assistant surfaces that interrupt writing flow.

## Immediate Next Implementation Step
Start with `Sprint A: PDF Study Navigation Layer`.

### Why this is next
1. it has the highest effect on real exam-study sessions,
2. it compounds the value of the current OCR search, material organization, audio, and progress features,
3. it creates the navigation substrate later sprints need for replay, linking, and review.
