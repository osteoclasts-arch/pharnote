# Pharnote Master Execution Prompt

You are building `pharnote`, the first-party iPad note-taking app for `pharnode`.

## Product Identity
- `pharnode` is the adaptive AI learning engine.
- `pharnote` is the iPad-native learning workspace where students read, write, solve, annotate, and generate evidence of understanding.
- `pharnote` is not a generic notebook clone. It is the highest-quality handwriting and PDF study workspace whose outputs are interpretable by pharnode.

## Mission
Build an iPadOS-first note-taking and PDF study app that can compete with and surpass Goodnotes-class polish by combining:
1. delightful handwriting and document UX,
2. reliable local-first performance,
3. page-level learning evidence capture,
4. one-tap analysis into the pharnode pipeline,
5. adaptive feedback and review loops.

## Non-Negotiables
1. Do not clone Goodnotes UI.
2. Follow Apple iPadOS, Apple Pencil, Scribble, PencilKit, and PDFKit interaction expectations.
3. Ship only in small, buildable increments.
4. Keep the app useful without network connectivity.
5. AI analysis must enhance user control, not replace it.
6. The app must feel emotionally attractive: cute, soft, premium, study-focused, and clearly branded.

## Product Pillars
1. Best-in-class handwriting on iPad.
2. Best-in-class PDF problem-solving workflow.
3. Structured learning evidence at page and session level.
4. Deep pharnode integration for concept graph analysis.
5. Adaptive review that closes the loop after note-taking.

## UX North Star
The student should feel:
- "Writing here is more pleasant than in any other app."
- "This app understands what I studied."
- "After I finish a page, I know what I understood and what I missed."
- "My notes are not dead files. They become study intelligence."

## Core App Loops
### Loop A: Capture
Open document -> study -> write/annotate/highlight -> autosave.

### Loop B: Analyze
Tap Analyze -> package current page or selection -> send to pharnode -> receive insight -> mark weak nodes -> suggest next step.

### Loop C: Review
Open review queue -> revisit weak pages -> compare previous attempt -> restudy -> reanalyze.

## Interface Priorities
### Library
- Must feel like a study desk, not a filesystem.
- Prioritize recency, active subjects, weak concepts, pending analysis, and review due items.

### Blank Note Workspace
- Minimal interruption while writing.
- Tooling must feel custom and premium.
- Page thumbnails, bookmarks, and quick analyze must be always reachable.

### PDF Workspace
- Optimized for solving, highlighting, margin writing, and fast navigation.
- Page context and analysis actions must be visible but non-intrusive.

### Insight Layer
- Insights must be grounded, visual, and actionable.
- Show concepts, estimated mastery, misconceptions, confidence, and next steps.

## Design Direction
Adopt a `Soft Study Atelier` direction:
- warm paper backgrounds,
- vivid but controlled brand blue,
- rounded floating panels,
- high-craft tool chrome,
- subtle motion with gentle spring,
- cute and memorable without becoming childish.

## Data Principles
1. Local-first note ownership.
2. Per-document package structure for portability.
3. App-level catalog/index for search, sessions, and analysis cache.
4. Page-level metadata, event logs, and thumbnails.
5. Explicit analysis bundles for pharnode integration.

## AI Principles
1. Explain what is sent for analysis.
2. Allow analyzing page, selection, or session scope.
3. Preserve user agency: accept, ignore, or retry results.
4. Represent uncertainty and evidence.
5. Never block the writing flow because analysis is unavailable.

## Delivery Mode
Execute in phases. Each phase must:
1. leave the app buildable,
2. improve one visible product layer,
3. avoid speculative infrastructure unless immediately needed,
4. include acceptance criteria,
5. include explicit tradeoffs.

## Immediate Execution Order
1. Phase 0: product definition, IA, data contracts, brand direction.
2. Phase 1: design system overhaul and library redesign.
3. Phase 2: handwriting workspace polish and custom tool UI.
4. Phase 3: PDF workspace polish and navigation quality.
5. Phase 4: analysis bundle creation and Analyze action.
6. Phase 5: insight surfaces and review loop.
7. Phase 6: performance, recovery, and quality hardening.

## Naming Rules
- App name: `pharnote`
- Parent platform: `pharnode`
- Keep the two products distinct in app identity, but deeply connected in data flow.

## Quality Bar
Before calling any phase complete, ask:
1. Is it more emotionally attractive than the previous version?
2. Is it faster or more reliable than before?
3. Does it make the pharnode integration story clearer?
4. Would a serious student prefer using this over a generic notes app for real study sessions?
