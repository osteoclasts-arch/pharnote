# Pharnote Data Collection Spec

## 1. Purpose
This document fixes the boundary between data that `pharnote` can collect immediately from public sources and data that must be generated inside the product through logging, labeling, and review loops.

The goal is not to write another generic dataset memo. The goal is to define what can be executed now, what must wait for app instrumentation, and what should be avoided.

## 2. Bottom Line
`pharnote` can be built with a strong internal analysis pipeline, but the data strategy must be split into three lanes.

1. Product-generated core data: must be collected by `pharnote` itself.
2. Public bootstrap datasets: can be used to initialize parts of the modeling stack, but cannot replace product data.
3. Public support data: can help ontology, textbook structure, aliases, and misconception lexicons.

What cannot be outsourced to the web:
1. learner-level `pharnote` handwriting behavior,
2. page-level study evidence from real `pharnote` sessions,
3. user correction loops,
4. recall traces tied to `pharnote` pages,
5. long-horizon outcome data tied to `pharnote` concepts.

## 3. Current Pharnote State
Relevant local files already define a first-pass analysis surface:
- [AnalysisModels.swift](/Users/osteoclasts_/Desktop/coding/pharnote/pharnote/Models/AnalysisModels.swift)
- [AnalysisCenter.swift](/Users/osteoclasts_/Desktop/coding/pharnote/pharnote/Services/AnalysisCenter.swift)
- [AnalysisQueueStore.swift](/Users/osteoclasts_/Desktop/coding/pharnote/pharnote/Services/AnalysisQueueStore.swift)
- [BlankNoteEditorViewModel.swift](/Users/osteoclasts_/Desktop/coding/pharnote/pharnote/ViewModels/BlankNoteEditorViewModel.swift)
- [PDFEditorViewModel.swift](/Users/osteoclasts_/Desktop/coding/pharnote/pharnote/ViewModels/PDFEditorViewModel.swift)

The app already has these usable fields in `AnalysisBundle`:
1. `document` metadata
2. `page` context
3. `drawingStats`
4. `typedBlocks` / `pdfTextBlocks` / `ocrTextBlocks`
5. `studyIntent`
6. dwell / revisit / tool usage / undo / redo / lasso / copy / paste counts
7. page context and privacy flags

The app is still missing the data structures required for production DKT and internal intelligence:
1. canonical `subject_id`, `unit_id`, `concept_id[]`
2. `problem_attempt_id` and attempt-level outcomes
3. `recall_attempt_id` and recall outcomes
4. persistent raw event store with event ordering guarantees
5. normalized page/session feature rows
6. review task generation records
7. user correction records with versioning
8. dataset / annotation / model lineage tables

## 4. Collection Lanes

### 4.1 Lane A: Product-Generated Core Data
This lane is mandatory. Without it, `pharnote` will not have its own intelligence layer.

#### A1. Raw Event Log
Purpose:
- preserve user interaction traces before any aggregation.

Must come from product instrumentation:
1. page enter / exit
2. tool selected
3. stroke batch committed
4. undo / redo
5. lasso used
6. copy / paste
7. bookmark toggled
8. analyze requested
9. problem attempt started / finished
10. recall started / finished
11. correction submitted
12. review task opened / completed

Do not try to collect this from external sources.

#### A2. Normalized Page / Session Features
Purpose:
- derive stable features from noisy event streams.

Examples:
1. dwell time
2. active edit time
3. stroke density
4. erase ratio
5. highlight coverage
6. revisit count
7. revision intensity
8. navigation pattern
9. dominant study mode
10. inferred page role

#### A3. DKT Training Rows
Purpose:
- build learner x concept x time sequences.

Required fields:
1. `learner_id`
2. `concept_id`
3. `timestamp`
4. `outcome`
5. `session_id`
6. optional feature bundle

Without this, there is no real DKT.

#### A4. Recognition Gold Set
Purpose:
- train subject/unit/study-mode/page-role classifiers.

Required labels:
1. `subject_id`
2. `unit_id`
3. `concept_ids`
4. `study_mode`
5. `page_role`
6. optional `quality_score`

#### A5. Problem Attempt Dataset
Purpose:
- analyze problem solving quality and drive concept-level outcomes.

Required fields:
1. `problem_attempt_id`
2. `page_id`
3. `concept_ids`
4. `started_at`
5. `ended_at`
6. `correctness`
7. `partial_score`
8. `self_confidence`
9. `revision_count`

#### A6. Recall / Memorization Dataset
Purpose:
- model forgetting and review readiness.

Required fields:
1. `recall_attempt_id`
2. `page_id`
3. `concept_ids`
4. `cue_type`
5. `recall_result`
6. `response_latency_ms`
7. `self_confidence`
8. `scheduled_interval`

#### A7. User Correction Dataset
Purpose:
- close the loop when automatic recognition is wrong.

Required fields:
1. `target_type`
2. `target_ref_id`
3. `before_value`
4. `after_value`
5. `user_id`
6. `created_at`
7. `source_model_version`

Execution status:
- Not collectible from the web.
- Must be implemented in `pharnote`.

### 4.2 Lane B: Public Bootstrap Datasets
This lane is useful for baseline models, pretraining, evaluation sanity checks, and feature design. It does not replace lane A.

#### B1. EdNet
Source:
- [EdNet GitHub repository](https://github.com/riiid/ednet)

Why it matters:
1. Korean educational interaction data
2. very large learner sequences
3. action-level variants (`KT2` to `KT4`)
4. question tags and content tables

Good use cases:
1. baseline KT pretraining
2. action vocabulary design
3. sequence feature sanity checks
4. concept-tag sequence experiments

Bad use cases:
1. handwriting modeling
2. page-level note understanding
3. `pharnote` stroke behavior inference

Acquisition note:
- Public repository documents download links.
- Use only the official source links documented in the repository.

#### B2. ASSISTments datasets
Sources:
- [2017 ASSISTments competition dataset page](https://sites.google.com/view/assistmentsdatamining/dataset)
- [ASSISTments data archive](https://sites.google.com/site/assistmentsdata/)
- [E-TRIALS data terms](https://sites.google.com/view/e-trials/data-sets)

Why it matters:
1. mature public KT benchmark family
2. many published baselines
3. useful for concept/outcome sequence modeling

Good use cases:
1. KT baseline training
2. evaluation harness design
3. sequence schema validation

Bad use cases:
1. direct transfer of labels to Korean curriculum
2. note-taking behavior modeling

Acquisition note:
- Some datasets are public.
- Some require agreeing to terms or contacting the maintainers.
- Treat as conditional public data, not fully frictionless data.

#### B3. DataShop public datasets
Sources:
- [DataShop FAQ](https://pslcdatashop.web.cmu.edu/about/faq.html)
- [DataShop Web Services](https://pslcdatashop.web.cmu.edu/about/webservices.html)
- [DataShop public home](https://pslcdatashop.web.cmu.edu/)

Why it matters:
1. many public educational interaction datasets
2. strong metadata and web-service access patterns
3. useful for evaluation and schema benchmarking

Good use cases:
1. public dataset discovery
2. schema benchmarking
3. transaction-to-training ETL prototyping

Constraints:
1. some datasets are public and freely viewable according to the FAQ
2. API use requires a DataShop account and access keys
3. private datasets still require explicit access

#### B4. Junyi dataset
Source:
- [Junyi dataset site](https://sites.google.com/view/junyidataset/home)

Status:
- Currently not a clean immediate source from this environment because the site redirects to Google sign-in.

Use:
- Keep on shortlist, but do not treat as an immediate collection source until access flow is verified.

### 4.3 Lane C: Public Support Data
This lane helps recognition, ontology, textbook matching, and explanation quality.

#### C1. OpenStax
Source:
- [OpenStax licensing](https://openstax.org/licensing)

Use:
1. OER textbook structures
2. section headings
3. concept phrasing
4. textbook TOC patterns

Why it is useful:
- Good source of legally reusable structured textbook content.

#### C2. Open Textbook Library
Source:
- [Open Textbook Library](https://open.umn.edu/opentextbooks)

Use:
1. textbook metadata
2. subject grouping
3. open-license book discovery
4. title-author-ISBN mapping

Why it is useful:
- It explicitly describes open textbooks as licensed for free use and adaptation.

#### C3. Aladin TTB API
Source:
- [Aladin TTB API guide](https://www.aladin.co.kr/ttb/apiguide.aspx)

Use:
1. title / author / ISBN metadata enrichment
2. book matching for imported PDFs
3. candidate textbook lookup

Constraints:
1. API terms must be respected.
2. Use metadata, not copyrighted book body extraction.
3. Keep this in the metadata lane, not the content lane.

#### C4. Data4Library
Source:
- [도서관 정보나루](https://www.data4library.kr/)

Use:
1. bibliographic metadata
2. ISBN-based enrichment
3. library-held book metadata cross-checks

Constraints:
1. verify API registration and rate limits before automation
2. do not assume content-body access

#### C5. Public student communities such as Orbi
Source:
- [Orbi robots.txt](https://orbi.kr/robots.txt)

Allowed posture:
1. manual review first
2. robots-aware collection only
3. alias / shorthand / misconception phrase extraction only
4. no use as DKT ground truth

Not allowed posture:
1. bulk learner behavior inference
2. storing personal profiles or user identifiers
3. collecting from disallowed paths
4. assuming robots alone resolves copyright or terms questions

Use only after manual legal review:
1. subject aliases
2. unit aliases
3. exam slang
4. misconception phrase candidates
5. explanation pattern fragments

## 5. What I Can Collect Now
I can proceed immediately on these items without waiting for another external assistant.

### Immediate and safe
1. official public-source survey and source shortlist
2. source manifest with access conditions
3. public bootstrap dataset acquisition checklist
4. metadata-only support source plan
5. ontology starter structure
6. app-side logging schema and ETL spec

### Requires pharnote implementation first
1. real `pharnote` learner sequences
2. handwriting-derived behavior rows
3. problem attempt outcomes from in-app workflows
4. recall traces tied to `pharnote` pages
5. user correction loops

### Requires manual legal/product review first
1. community scraping beyond light manual sampling
2. commercial textbook body extraction
3. automated crawling on ambiguous terms sites
4. any source requiring login, paywall, or bypass

## 6. Execution Order

### P0
1. Freeze production event schema.
2. Add persistent raw event store on-device.
3. Add canonical subject/unit/concept IDs to analysis artifacts.
4. Add problem-attempt and recall-attempt records.
5. Add user-correction persistence.
6. Create public source manifest and acquisition checklist.
7. Acquire one bootstrap KT dataset from an official source.
8. Acquire one OER textbook metadata source.

### P1
1. Build normalized feature generation.
2. Build first annotation guideline.
3. Build concept linkage rules.
4. Build first DKT training-row generator.
5. Build review-task generator.

### P2
1. Add calibrated recognizers.
2. Add support lexicon expansion from reviewed public sources.
3. Add source/version lineage tracking.

## 7. Recommended Next Deliverables
The next documents that should exist in the repo are:
1. `05_PRODUCTION_EVENT_SCHEMA.md`
2. `06_PRODUCTION_DB_SCHEMA.md`
3. `07_ANNOTATION_GUIDELINE.md`
4. `08_PUBLIC_SOURCE_ACQUISITION_CHECKLIST.md`

## 8. Source Summary
| Source | Category | Immediate usability | What it gives us | Main constraint |
| --- | --- | --- | --- | --- |
| EdNet | bootstrap DKT | yes | Korean action sequences | no handwriting / no page notes |
| ASSISTments | bootstrap DKT | conditional | benchmark KT sequences | terms / request flow may apply |
| DataShop public datasets | bootstrap DKT | conditional | many public educational logs | account/API keys for automation |
| Junyi | bootstrap DKT | no, not yet | KT benchmark family | current access flow requires verification |
| OpenStax | support | yes | open textbook structure/content | not Korean curriculum specific |
| Open Textbook Library | support | yes | open textbook metadata | metadata discovery, not learner traces |
| Aladin TTB API | support | yes, after key/terms review | book metadata enrichment | metadata only |
| Data4Library | support | yes, after API review | ISBN/library metadata | registration and limits |
| Orbi | support | manual-review only | aliases and misconception phrases | legal/terms review still required |

## 9. Final Rule
If a source does not provide `learner_id + concept_id + timestamp + outcome`, it is not a core DKT dataset.

If a source does not come from `pharnote`, it does not represent `pharnote` handwriting behavior.

If a source is a community site, treat it as support data until proven otherwise.
