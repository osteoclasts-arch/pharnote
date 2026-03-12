from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class DoctrineScoreBundle(StrictModel):
    reusability_score: float = 0.0
    specificity_score: float = 0.0
    evidence_score: float = 0.0
    source_diversity_score: float = 0.0
    problem_alignment_score: float = 0.0
    overall_score: float = 0.0


class ProblemDbSchemaProfile(StrictModel):
    backend: Literal["fixture", "supabase", "database_url"]
    table_name: str
    introspection_mode: Literal["fixture", "information_schema", "sampled_rows"]
    available_columns: List[str]
    metadata_keys: List[str]
    resolved_fields: Dict[str, Optional[str]]
    resolved_metadata_fields: Dict[str, Optional[str]]
    warnings: List[str] = Field(default_factory=list)
    excluded_capabilities: List[str] = Field(default_factory=list)
    sample_row_count: int = 0


class ScopedProblem(StrictModel):
    problem_id: str
    source_record_id: str
    year: int
    month: int
    exam_type: str
    subject: str
    question_number: int
    stem: str
    choices: List[str]
    answer: Optional[str] = None
    solution_outline: Optional[str] = None
    concept_tags: List[str] = Field(default_factory=list)
    points: int
    common_section: bool
    metadata: Dict[str, Any] = Field(default_factory=dict)


class ProblemDoctrineSeed(StrictModel):
    seed_id: str
    problem_id: str
    bucket: Literal["required_doctrines", "anti_patterns", "verification_doctrines"]
    taxonomy_group: str
    taxonomy_code: str
    condition: str
    action: str
    evidence_spans: List[str] = Field(default_factory=list)
    seed_confidence: float


class ProblemDoctrineSeedBundle(StrictModel):
    problem_id: str
    required_doctrines: List[ProblemDoctrineSeed] = Field(default_factory=list)
    anti_patterns: List[ProblemDoctrineSeed] = Field(default_factory=list)
    verification_doctrines: List[ProblemDoctrineSeed] = Field(default_factory=list)


class RawDoctrineSourceDocument(StrictModel):
    source_id: str
    source_type: Literal["community", "instructor", "founder"]
    author: str
    problem_ids: List[str]
    title: str
    body: str


class RawDoctrineCandidate(StrictModel):
    candidate_id: str
    problem_id: str
    source_type: Literal["problem_seed", "community", "instructor", "founder"]
    source_ref: str
    author: str
    raw_text: str
    source_reliability_tier: int
    taxonomy_group: Optional[str] = None
    taxonomy_code: Optional[str] = None
    evidence_spans: List[str] = Field(default_factory=list)
    rejection_reason: Optional[str] = None


class NormalizedDoctrineCandidate(StrictModel):
    candidate_id: str
    problem_id: str
    source_type: Literal["problem_seed", "community", "instructor", "founder"]
    condition: str
    action: str
    normalization_confidence: float
    source_ref: Optional[str] = None
    taxonomy_group: Optional[str] = None
    taxonomy_code: Optional[str] = None
    normalized_fingerprint: Optional[str] = None
    rejection_reason: Optional[str] = None


class DoctrineCluster(StrictModel):
    doctrine_id: str
    condition: str
    action: str
    supported_problem_ids: List[str]
    scores: DoctrineScoreBundle = Field(default_factory=DoctrineScoreBundle)
    approval_status: Literal["auto_approved", "review_needed", "rejected"] = "review_needed"
    supporting_candidate_ids: List[str] = Field(default_factory=list)
    taxonomy_codes: List[str] = Field(default_factory=list)
    source_types: List[str] = Field(default_factory=list)
    merge_evidence: List[Dict[str, Any]] = Field(default_factory=list)
    evidence_summary: List[str] = Field(default_factory=list)


class ApprovalDecision(StrictModel):
    doctrine_id: str
    approval_status: Literal["auto_approved", "review_needed", "rejected"]
    rejection_reasons: List[
        Literal[
            "motivational_only",
            "too_vague",
            "too_item_specific",
            "unsupported_by_problem",
            "low_evidence",
        ]
    ] = Field(default_factory=list)
    triggered_rules: List[str] = Field(default_factory=list)
    threshold_trace: Dict[str, Any] = Field(default_factory=dict)
    override_note: Optional[str] = None


class PayloadDoctrineEntry(StrictModel):
    doctrine_id: Optional[str] = None
    taxonomy_code: Optional[str] = None
    condition: str
    action: str
    evidence_summary: str


class ProblemDoctrinePayload(StrictModel):
    problem_id: str
    recommended_doctrine_ids: List[str]
    required_doctrines: List[PayloadDoctrineEntry]
    common_missed_doctrines: List[PayloadDoctrineEntry]
