# Pharnote Product Spec

## 1. Summary
`pharnote` is an iPadOS-first handwriting and PDF workspace built by `pharnode`.
It serves two jobs at once:
1. provide a premium writing and annotation experience,
2. capture structured evidence of how a student works so the pharnode engine can support metacognition with context, patterns, and later insight.

The product is defined first by GoodNotes-class writing quality and document workflow, then by how quietly it captures enough evidence to help the user reflect on understanding later.

## 2. Product Thesis
Most note apps stop at storage and retrieval.
Pharnote must add a second layer without getting in the way:

Write -> organize -> capture evidence -> analyze when requested -> reflect with context.

## 3. Target Users
### Primary
- high-school students preparing for exams,
- college-bound students using PDF materials and handwritten problem solving,
- students who revise notes repeatedly and need help understanding what they actually know.

### Secondary
- tutors who review student work,
- self-directed learners using digital textbooks and problem sets.

## 4. Core Jobs To Be Done
1. When I solve on top of a PDF, I want writing to feel instant and natural.
2. When I finish a page, I want the app to preserve enough context to help me reflect on what I did later.
3. When I return later, I want important pages, progress, and page context surfaced clearly.
4. When I work across multiple notes, I want pharnode to connect the evidence into one understanding model.

## 5. Product Pillars
### Pillar A: Joyful Capture
Handwriting, PDF annotation, page navigation, and tool switching must feel fast, stable, and premium.

### Pillar B: Structured Evidence
A page is not just an image. It is a study artifact with content, behavior, and context.

### Pillar C: Metacognitive Insight
Analysis should help the user interpret what was written, what context it belongs to, and what may deserve a second look.

### Pillar D: Quiet Intelligence
The intelligence layer should collect and structure evidence without turning the app into a tutoring workflow surface.

## 6. Differentiation Against the Category
### What generic note apps do well
- handwriting,
- document organization,
- search,
- annotation,
- sync.

### What pharnote must do better
- interpret the meaning of study activity,
- link pages to concept graph nodes,
- estimate understanding from real work traces,
- preserve context so later reflection is grounded in actual evidence.

## 7. Experience Principles
1. Writing comes first. Analysis never gets in the way of pen flow.
2. Pages are intelligent objects, not dead canvases.
3. Analysis must be optional, visible, and trustworthy.
4. The UI should feel soft, cute, premium, and unmistakably branded.
5. Intelligence should stay behind the writing experience until the user asks for it.

## 8. Information Architecture
### Top-level app areas
1. Home Library
2. Blank Notes
3. PDF Workspaces
4. Analysis Queue
5. Settings

### Home Library sections
1. Recent Documents
2. Continue Studying
3. Recent Insights
4. Subjects / Collections
5. Imported PDFs
6. Draft Notes

### Per-document structure
1. Document Overview
2. Page Canvas / PDF Page
3. Page Thumbnails
4. Tool Dock
5. Analyze Action
6. Insight Surface
7. Progress Markers

## 9. Screen Definitions
### 9.1 Library Home
Purpose:
- entry point for study sessions,
- overview of current learning state,
- fast navigation to active work.

Must show:
1. branded hero or desk-like header,
2. recent documents,
3. recent page insights,
4. pages awaiting analysis,
5. subject filters,
6. create / import actions.

Success criteria:
- opening the app should immediately suggest what to do next.

### 9.2 Blank Note Workspace
Purpose:
- freeform writing,
- concept summaries,
- derivations,
- original note creation.

Must support:
1. instant handwriting,
2. multi-page management,
3. thumbnails,
4. bookmarks,
5. custom tool dock,
6. analyze page,
7. page state badges.

### 9.3 PDF Workspace
Purpose:
- textbook reading,
- problem solving,
- margin note-taking,
- highlighting and extraction.

Must support:
1. smooth page navigation,
2. PDF text search,
3. handwriting overlay,
4. thumbnail rail,
5. bookmarks,
6. analyze page or selection,
7. study-intent tagging.

### 9.4 Analyze Sheet
Purpose:
- explicit user-controlled analysis trigger.

Choices:
1. analyze current page,
2. analyze selected region,
3. analyze recent session,
4. attach study intent.

Must communicate:
1. what data is being sent,
2. what the user will receive back,
3. whether the request is local-only, queued, or online.

### 9.5 Insight Surface
Purpose:
- show page-level and concept-level understanding.

Must show:
1. concept nodes,
2. estimated mastery,
3. confidence,
4. likely misconception candidates,
5. recommended next actions,
6. analysis evidence,
7. open-in-pharnode link for deeper graph exploration.

## 10. Design System Direction
### Brand tone
- soft,
- optimistic,
- premium,
- study-focused,
- precise.

### Emotional impression
The app should feel like a highly curated digital study desk.

### Visual ingredients
1. paper-like warm backgrounds,
2. bright controlled blue accent,
3. rounded floating surfaces,
4. tactile tool buttons,
5. clear hierarchy between canvas and chrome,
6. tiny moments of delight in transitions.

### Accessibility rules
1. support Dynamic Type where it does not break workspace ergonomics,
2. high-contrast variants for tags and badges,
3. large hit targets,
4. color is never the sole indicator of learning state.

## 11. Learning Evidence Model
Each page should accumulate multiple evidence layers.

### Content evidence
1. stroke data,
2. typed text,
3. PDF source text,
4. OCR text when needed,
5. highlights,
6. bookmarks,
7. selection history.

### Behavior evidence
1. dwell time,
2. revisit count,
3. erase ratio,
4. stroke density,
5. tool usage mix,
6. page order flow,
7. zoom and pan behavior,
8. copy/paste or lasso actions.

### Context evidence
1. subject,
2. document role,
3. study intent,
4. exam proximity,
5. adjacent pages,
6. previous analyses.

## 12. Pharnode Integration Model
### Integration goals
1. infer what topic the student studied,
2. estimate depth of understanding,
3. detect instability or misconception patterns,
4. recommend next study actions,
5. write results back to pharnote and pharnode.

### Integration rules
1. do not force an app switch for standard analysis,
2. use API / queue-driven analysis,
3. open pharnode only for deeper graph views or curriculum actions,
4. preserve offline queueing.

## 13. Local Data Architecture
### Current state
- document packages,
- JSON library index,
- local drawing data,
- thumbnail cache.

### Required target state
#### App catalog
Use a lightweight catalog store for:
1. document registry,
2. search indexes,
3. study sessions,
4. page events,
5. analysis requests and cached results,
6. review queue.

#### Document package
Per document package should eventually contain:
1. `Document.json`
2. `Pages/<page-id>/drawing.data`
3. `Pages/<page-id>/page-meta.json`
4. `Pages/<page-id>/thumbnail.webp`
5. `PDF/original.pdf`
6. `Analysis/`
7. `Attachments/`

## 14. Performance Targets
1. workspace open in under 1 second for recent documents,
2. page switch should feel near-instant,
3. writing must not perform heavy work on stroke callbacks,
4. thumbnail generation must stay off the critical path,
5. analysis package creation must be incremental,
6. autosave must be crash-resilient.

## 15. Trust and AI UX Requirements
1. analysis must state scope and purpose,
2. uncertainty must be represented,
3. users can dismiss, retry, or ignore results,
4. offline fallback must be clear,
5. privacy messaging must be concrete,
6. no fabricated certainty.

## 16. Success Metrics
### Capture quality
1. note creation retention,
2. session length,
3. return-to-document rate,
4. page revisit rate.

### Insight quality
1. analyze button usage,
2. acceptance of recommended next actions,
3. reanalysis rate after review,
4. concept mastery confidence calibration.

### Product strength
1. weekly active students,
2. documents analyzed per week,
3. review completion rate,
4. cross-app continuation from pharnote to pharnode.

## 17. Near-Term Milestones
### Milestone 1
Pharnote visually feels like a real product.

### Milestone 2
Blank note and PDF workspaces feel clearly superior to the current prototype.

### Milestone 3
Analyze button exists and packages page-level evidence reliably.

### Milestone 4
Pharnode results are rendered back in app.

### Milestone 5
Review loop begins to affect student behavior.
